#!/bin/bash
# shellcheck disable=SC2034
dns_edgecenter_info='EdgeCenter
Site: https://edgecenter.ru
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_edgecenter
Options:
 EDGECENTER_API_KEY auth APIKey
Author: Aleksey Pletnev <alpletnyov@yandex.ru>
'

EDGECENTER_API="https://api.edgecenter.ru"
DOMAIN_TYPE=
DOMAIN_MASTER=

########  Public functions #####################

#Usage: dns_edgecenter_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_edgecenter_add() {
  _info "Using EdgeCenter"

  if ! _dns_edgecenter_init_check; then
    return 1
  fi

  zone="$(_dns_edgecenter_get_zone_name "$1")"
  if [ -z "$zone" ]; then
    _err "Missing DNS zone at EdgeCenter. Please log into your control panel and create the required DNS zone for the initial setup."
    return 1
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2

  _debug zone "$zone"
  _debug host "$host"
  _debug record "$record"

  _info "Adding the TXT record for $1"
  _dns_edgecenter_http_api_call "post" "dns/v2/zones/$zone/$host.$zone/txt" "{\"resource_records\": [ { \"content\": [\"$record\"] } ], \"ttl\": 60 }"
  if _contains "$response" "\"error\":\"rrset is already exists\""; then
    _dns_edgecenter_http_api_call "put" "dns/v2/zones/$zone/$host.$zone/txt" "{\"resource_records\": [ { \"content\": [\"$record\"] } ], \"ttl\": 60 }"
    return 1
  fi  
  if _contains "$response" "\"exception\":"; then
    _err "Record cannot be added."
    return 1
  fi
  _info "Added."

  return 0
}

#Usage: dns_edgecenter_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_edgecenter_rm() {
  _info "Using EdgeCenter"

  if ! _dns_edgecenter_init_check; then
    return 1
  fi

  if [ -z "$zone" ]; then
    zone="$(_dns_edgecenter_get_zone_name "$1")"
    if [ -z "$zone" ]; then
      _err "Missing DNS zone at EdgeCenter. Please log into your control panel and create the required DNS zone for the initial setup."
      return 1
    fi
  fi

  host="$(echo "$1" | sed "s/\.$zone\$//")"
  record=$2
  
  _debug zone "$zone"
  _debug host "$host"
  
  _dns_edgecenter_http_api_call "delete" "dns/v2/zones/$zone/$host.$zone/txt"
  
  if ! _contains "$response" "\"status\":\"Success\""; then
    _err "The TXT record for $host cannot be deleted."
  else
    _info "Deleted."
  fi

  return 0
}

####################  Private functions below ##################################
_dns_edgecenter_init_check() {
  if [ -n "$EDGECENTER_INIT_CHECK_COMPLETED" ]; then
    return 0
  fi

  EDGECENTER_API_KEY="${EDGECENTER_API_KEY:-$(_readaccountconf_mutable EDGECENTER_API_KEY)}"
  if [ -z "$EDGECENTER_API_KEY" ]; then
    _err "You don't specify edgecenter api key yet."
    _err "Please create you id and password and try again."
    return 1
  fi

  _dns_edgecenter_http_api_call "get" "dns/v2/clients/me/features"

  if ! _contains "$response" "\"id\":"; then
    _err "Invalid EDGECENTER_API_KEY. Please check."
    return 1
  fi

  # save the api id and password to the account conf file.
  _saveaccountconf_mutable EDGECENTER_API_KEY "$EDGECENTER_API_KEY"

  EDGECENTER_INIT_CHECK_COMPLETED=1

  return 0
}

_dns_edgecenter_get_zone_name() {
  i=2
  while true; do
    zoneForCheck=$(printf "%s" "$1" | cut -d . -f $i-100)

    if [ -z "$zoneForCheck" ]; then
      return 1
    fi

    _debug zoneForCheck "$zoneForCheck"

    _dns_edgecenter_http_api_call "get" "dns/v2/zones/$zoneForCheck"

    if ! _contains "$response" "\"error\":\"get zone by name: zone is not found\""; then
      echo "$zoneForCheck"
      return 0
    fi

    i=$(_math "$i" + 1)
  done
  return 1
}

_dns_edgecenter_http_api_call() {
  method=$1
  api_method=$2
  body=$3

  _debug EDGECENTER_API_KEY "$EDGECENTER_API_KEY"
  
  export _H1="Authorization: APIKey $EDGECENTER_API_KEY"

  if _contains "$method" "get"; then
	response="$(_get "$EDGECENTER_API/$api_method")"
  fi
  
  if _contains "$method" "post"; then
	response="$(_post "$body" "$EDGECENTER_API/$api_method")"
  fi
  
  if _contains "$method" "delete"; then
	response="$(_post "" "$EDGECENTER_API/$api_method" "" "DELETE")"
  fi
  
  if _contains "$method" "put"; then
	response="$(_post "" "$EDGECENTER_API/$api_method" "" "PUT")"
  fi

  _debug response "$response"

  return 0
}
