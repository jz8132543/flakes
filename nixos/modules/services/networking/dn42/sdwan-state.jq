def uint:
  type == "number" and . >= 0 and . <= 9007199254740991 and floor == .;

def peer_name:
  type == "string" and test("^[a-z0-9][a-z0-9_-]{0,62}$");

def ipv4:
  type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")
  and all(split(".")[]; tonumber >= 0 and tonumber <= 255);

def ipv6:
  if type != "string" then false else
    (if contains(".") then
       (try capture("^(?<head>.*:)(?<tail>[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)$") catch null)
       | if . != null and (.tail | ipv4) then .head + "0:0" else "invalid" end
     else . end) as $address
    | ($address | split("::")) as $parts
    | if ($parts | length) == 1 then
        ($address | split(":")) as $groups
        | ($groups | length) == 8 and all($groups[]; test("^[A-Fa-f0-9]{1,4}$"))
      elif ($parts | length) == 2 then
        ($parts | map(if . == "" then [] else split(":") end)) as $groups
        | ($groups | flatten | length) < 8
          and all($groups[][]; test("^[A-Fa-f0-9]{1,4}$"))
      else false end
  end;

def endpoint_address:
  type == "string" and length > 0
  and test("^[A-Za-z0-9_.:%\\[\\]-]+$");

def port:
  uint and . >= 1 and . <= 65535;

def address:
  endpoint_address and
  (if contains(":") then ipv6
   elif test("^[0-9.]+$") then ipv4
   else test("^[A-Za-z0-9_][A-Za-z0-9_.-]*$") end);

def raw_endpoint:
  if type != "string" then false
  elif startswith("[") then
    (try capture("^\\[(?<address>[^]]+)\\](?::(?<port>[0-9]+))?$") catch null)
    | . != null and (.address | ipv6)
      and ((.port // "4500") | tonumber | port)
  elif (split(":") | length) == 2 then
    split(":") | (.[0] | address)
      and (.[1] | test("^[0-9]+$") and (tonumber | port))
  else address end;

def endpoints:
  if type == "object" then
    length <= 9
    and all(to_entries[];
      (.key | peer_name) and (.value | raw_endpoint))
  elif type == "array" then
    length <= 9
    and ([.[].name] | length == (unique | length))
    and all(.[];
      type == "object" and (.name | peer_name)
      and (if .addr != null then .addr | address else .value | raw_endpoint end)
      and ((.port // 4500) | port)
      and ((.family // "ipv4") | . == "ipv4" or . == "ipv6"))
  else false end;

def peers:
  type == "object"
  and all(to_entries[];
    (.key | peer_name)
    and (.value | type == "object"
      and (.id | uint and . >= 1 and . <= 99)
      and (.dn42_ip4 | ipv4)
      and ((.dn42_ip6 // "") | type == "string"
        and (. == "" or ipv6))
      and ((.endpoints // {}) | endpoints)
      and ((.nat_t_port // 4500) | port)
      and ((.ike_port // 500) | port)
      and ((.build_time // 0) | uint)
      and ((.updated_at // 0) | uint)
      and ((.last_seen // 0) | uint)
      and ((.lease_expires_at // 0) | uint)))
  and ([.[].id] | length == (unique | length));

def leased:
  with_entries(
    .value.last_seen = (if .value.lease_expires_at != null
        then .value.last_seen // .value.updated_at // 0
        else .value.updated_at // 0 end)
    | .value.build_time = (.value.build_time // 0)
    | .value.updated_at = (.value.updated_at // 0)
    | .value.lease_expires_at = (.value.lease_expires_at //
        (if .value.updated_at > 0 then .value.updated_at + $ttl else 0 end))
    | select(.value.lease_expires_at > $now));

def rank:
  [.last_seen, .build_time, .lease_expires_at,
    (walk(if type == "object" then to_entries | sort_by(.key) | from_entries else . end) | tojson)];

def merge($incoming):
  reduce ($incoming | to_entries[]) as $item (.;
    if .[$item.key] == null or (($item.value | rank) > (.[$item.key] | rank))
    then .[$item.key] = $item.value else . end);

if $action == "validate" then
  if length == 1 and (.[0] | peers and ($mode != "register" or length == 1)) then true
  else error("invalid SD-WAN node map") end
elif $action == "update" then
  .[0] as $cache | .[1] as $bootstrap | .[2] as $previous_seeds | .[3] as $incoming
  | ($bootstrap | with_entries(
      .value.last_seen = 0
      | .value.updated_at = 0
      | .value.lease_expires_at =
          ($previous_seeds[.key].lease_expires_at // ($now + $ttl)))) as $seeds
  | (($cache | leased) | merge($seeds | leased)) as $base
  | (if $mode == "register" then
       $base + ($incoming | with_entries(
         .value.build_time = (.value.build_time // 0)
         | .value.updated_at = $now
         | .value.last_seen = $now
         | .value.lease_expires_at = ($now + $ttl)))
     else $base | merge($incoming | leased) end) as $result
  | if ($result | peers) then {state: $result, seeds: $seeds}
    else error("conflicting SD-WAN node IDs or invalid state") end
else error("unknown SD-WAN state operation") end
