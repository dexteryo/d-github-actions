#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: env-power.sh <schedule-group> <start|stop> <wait>" >&2
  exit 2
fi

group=$1
action=$2
wait_for_targets=$3

if ! [[ "$group" =~ ^[0-9A-Za-z_.-]{1,64}$ ]]; then
  echo "schedule-group must be 1 to 64 letters, digits, hyphens, underscores or dots: $group" >&2
  exit 2
fi

case "$action" in
  start | stop) ;;
  *)
    echo "action must be start or stop: $action" >&2
    exit 2
    ;;
esac

case "$wait_for_targets" in
  true | false) ;;
  *)
    echo "wait must be true or false: $wait_for_targets" >&2
    exit 2
    ;;
esac

names=$(aws scheduler list-schedules --group-name "$group" --query 'Schedules[].Name' --output text)
mapfile -t schedules < <(printf '%s\n' "$names" | tr '\t' '\n' | sed -e '/^$/d' -e '/^None$/d' | sort)

targets_of() {
  local kind=$1 name
  for name in "${schedules[@]}"; do
    case "$name" in
      "$group-$action-$kind-"*)
        aws scheduler get-schedule --group-name "$group" --name "$name" --query 'Target.Input' --output text
        ;;
    esac
  done
}

database_inputs=$(targets_of db)
service_inputs=$(targets_of svc)
mapfile -t databases < <(printf '%s\n' "$database_inputs" | sed '/^$/d' | jq -r '.DbInstanceIdentifier')
mapfile -t services < <(printf '%s\n' "$service_inputs" | sed '/^$/d' | jq -r '[.Cluster, .Service, (.DesiredCount | tostring)] | @tsv')

if [ "${#databases[@]}" -eq 0 ] && [ "${#services[@]}" -eq 0 ]; then
  echo "no $action schedules found in schedule group $group" >&2
  exit 1
fi

database_status() {
  aws rds describe-db-instances --db-instance-identifier "$1" --query 'DBInstances[0].DBInstanceStatus' --output text
}

pending_databases=()

check_databases() {
  local identifier status verb=started
  [ "$action" = start ] || verb=stopped
  for identifier in "${databases[@]}"; do
    status=$(database_status "$identifier")
    case "$action:$status" in
      start:stopped | stop:available) pending_databases+=("$identifier") ;;
      start:available | start:starting | stop:stopped | stop:stopping) echo "database $identifier is already $status" ;;
      *)
        echo "database $identifier is $status and cannot be $verb now; nothing was changed" >&2
        exit 1
        ;;
    esac
  done
}

start_databases() {
  local identifier
  for identifier in "${pending_databases[@]}"; do
    echo "starting database $identifier"
    aws rds start-db-instance --db-instance-identifier "$identifier" > /dev/null
  done
  if [ "$wait_for_targets" = true ]; then
    for identifier in "${databases[@]}"; do
      echo "waiting for database $identifier"
      aws rds wait db-instance-available --db-instance-identifier "$identifier"
    done
  fi
}

stop_databases() {
  local identifier
  for identifier in "${pending_databases[@]}"; do
    echo "stopping database $identifier"
    aws rds stop-db-instance --db-instance-identifier "$identifier" > /dev/null
  done
}

scale_services() {
  local cluster service count
  for line in "${services[@]}"; do
    IFS=$'\t' read -r cluster service count <<< "$line"
    echo "setting $service in $cluster to $count tasks"
    aws ecs update-service --cluster "$cluster" --service "$service" --desired-count "$count" --query 'service.serviceName' --output text > /dev/null
  done
  if [ "$wait_for_targets" = true ]; then
    for line in "${services[@]}"; do
      IFS=$'\t' read -r cluster service count <<< "$line"
      echo "waiting for $service to settle"
      aws ecs wait services-stable --cluster "$cluster" --services "$service"
    done
  fi
}

[ "${#databases[@]}" -eq 0 ] || check_databases

if [ "$action" = start ]; then
  [ "${#databases[@]}" -eq 0 ] || start_databases
  [ "${#services[@]}" -eq 0 ] || scale_services
else
  [ "${#services[@]}" -eq 0 ] || scale_services
  [ "${#pending_databases[@]}" -eq 0 ] || stop_databases
fi

echo "$group: $action done"
