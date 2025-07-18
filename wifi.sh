#!/bin/bash

# Параметры

if_name=$(nmcli dev status | grep "wifi " | awk '{print $1}')
PING_COUNT=3
PING_HOST="ya.ru"
PING_IP="77.88.8.8"

wifi_networks=("WIFI-1" "WIFI-2" "WIFI-3" "WIFI-4")

CONNECT_TIMEOUT=20

ZABBIX_CONFIG="/etc/zabbix/zabbix_agentd.conf"


# Проверка получения IP и что IP != 0.0.0.0

check_ip() {
  local if_name=$1
  local ipv4

  # Получение ip интерфейса

  ipv4=$(ip a show $if_name | grep "inet " | awk '{print $2}' | cut -d '/' -f 1)
  
  if [[ -z $ipv4 ]]; then
      return 1
  fi

  if [[ "$ipv4" == "0.0.0.0" ]]; then
      return 1
  fi

  return 0
}

# Подключение к SSID

connect_wifi() {
  local ssid="$1"
  nmcli device wifi connect "$ssid" > /dev/null
  #echo "$CONNECT_TIMEOUT секунд таймаут"
  sleep $CONNECT_TIMEOUT

  if check_ip; then
      return 0
  else
      return 1
  fi

}

# Проверка ping

check_ping() {
  local target="$1"
  if ping -I "$if_name" -c "$PING_COUNT" -W 3 "$target" > /dev/null; then
      return 0
  else
      return 1
  fi
}

#  отправка в zabbix

send_result() {
  local ssid="$1"
  local value="$2"

  zabbix_sender -c "$ZABBIX_CONFIG" -k "wifi.$ssid" -o "$value"
}

# основной цикл

for ssid in "${wifi_networks[@]}"; do
    nmcli dev disconnect "$if_name" > /dev/null 2>&1
    #echo "Проверка $ssid"

    # в одной из сетей проверять нужно другие адреса

    if [[ "$ssid" == "WIFI-3" ]]; then
        CURRENT_PING_IP="8.8.8.8"
        CURRENT_PING_HOST="google.com"
    else
        CURRENT_PING_IP="$PING_IP"
        CURRENT_PING_HOST="$PING_HOST"
    fi

    if connect_wifi "$ssid"; then
        #echo "Успешное подключение к $ssid"
        
        if check_ip; then
            if_ip_addr=$(ip a show $if_name | grep "inet " | awk '{print $2}' | cut -d '/' -f 1)
            #echo "Получен IP адрес: $if_ip_addr"

            #echo "Проверка ping $CURRENT_PING_IP"
            if check_ping $CURRENT_PING_IP; then
                #echo "$CURRENT_PING_IP доступен"
                #echo "Проверка ping $CURRENT_PING_HOST"
                if check_ping $CURRENT_PING_HOST; then
                    #echo "$CURRENT_PING_HOST доступен"
                    #echo "Соединение с wifi сетью $ssid корректно работает"
                    send_result $ssid 0
                else
                    #echo "$CURRENT_PING_HOST - пинг не прошел"
                    send_result $ssid 3 # нет пинга по имени хоста (DNS)
                fi
            else
                #echo "$CURRENT_PING_IP - пинг не прошел"
                send_result $ssid 2 # нет пинга по IP
                continue
            fi
        else
            #echo "IP не получен"
            send_result $ssid 1 # не получен IP
        fi
    
    else
        #echo "Не удалось подключиться к сети $ssid"
        send_result $ssid 4 # не удалось подключиться
    fi

    #echo "Проверка следующей сети ..."
done

