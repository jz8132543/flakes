"""Prepare private Mihomo runtime configuration without changing credentials."""

import json
import os
from pathlib import Path
import re
import sys
import tempfile

import yaml


class ConfigLoader(yaml.SafeLoader):
    pass


# Match Mihomo's yaml.v3 string handling for YAML 1.1 boolean-like credentials.
ConfigLoader.yaml_implicit_resolvers = {
    key: [resolver for resolver in resolvers if resolver[0] != "tag:yaml.org,2002:bool"]
    for key, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
ConfigLoader.add_implicit_resolver(
    "tag:yaml.org,2002:bool",
    re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"),
    list("tTfF"),
)


def prepare_policy(config, policy):
    ports = policy["ports"]
    if (
        not isinstance(ports, list)
        or not ports
        or any(type(port) is not int or not 1 <= port <= 65535 for port in ports)
    ):
        raise ValueError("Invalid ports")
    ports = list(dict.fromkeys(ports))
    domain = policy["domain"]
    dn42_domain = policy["dn42Domain"]
    for name in (domain, dn42_domain):
        if (
            not isinstance(name, str)
            or len(name) > 253
            or (
                name
                and not re.fullmatch(
                    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
                    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*",
                    name,
                )
            )
        ):
            raise ValueError("Invalid domain")
    if not domain:
        raise ValueError("Missing domain")
    if not isinstance(config, dict):
        raise ValueError("Invalid configuration")
    original = config.get("rules", [])
    if not isinstance(original, list) or any(
        not isinstance(rule, str) for rule in original
    ):
        raise ValueError("Invalid rules")
    if not any(
        isinstance(adapter, dict) and adapter.get("name") == "PROXY"
        for key in ("proxies", "proxy-groups")
        for adapter in config.get(key, [])
    ):
        raise ValueError("Missing PROXY adapter")

    rules = [
        "IP-CIDR,172.20.0.0/14,DIRECT,no-resolve",
        "IP-CIDR,172.31.0.0/16,DIRECT,no-resolve",
        "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
        "IP-CIDR,fd00::/8,DIRECT,no-resolve",
        "GEOSITE,private,DIRECT",
        "GEOIP,private,DIRECT",
        "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
        "IP-CIDR,fc00::/7,DIRECT,no-resolve",
        "DOMAIN-SUFFIX,ts,DIRECT",
        "DOMAIN-SUFFIX,et,DIRECT",
    ]
    if dn42_domain:
        rules.append(f"DOMAIN-SUFFIX,{dn42_domain},DIRECT")
    rules.extend(
        f"AND,((NETWORK,TCP),(DST-PORT,{port}),(GEOIP,CN)),DIRECT" for port in ports
    )
    rules.extend(f"AND,((NETWORK,TCP),(DST-PORT,{port})),PROXY" for port in ports)

    # Reposition managed rules as one block, including when preparing an old output.
    removed = set(rules) | {f"DST-PORT,{port},DIRECT" for port in ports}
    retained = [
        rule
        for rule in original
        if ",".join(part.strip() for part in rule.split(",")) not in removed
    ]
    anchor = f"DOMAIN-SUFFIX,{domain.lower()},DIRECT"
    position = next(
        (
            index
            for index, rule in enumerate(retained)
            if ",".join(part.strip() for part in rule.split(",")).lower()
            == anchor.lower()
            or rule.split(",", 1)[0].strip() == "MATCH"
        ),
        len(retained),
    )
    return {**config, "rules": retained[:position] + rules + retained[position:]}


def prepare_file(source, destination, policy_path):
    source = Path(source)
    destination = Path(destination)
    if source.resolve() == destination.resolve():
        raise ValueError("Configuration input must remain immutable")
    if destination.parent.stat().st_mode & 0o777 != 0o700:
        raise ValueError("Runtime directory must be private")
    with policy_path.open(encoding="utf-8") as stream:
        policy = json.load(stream)
    text = source.read_bytes().decode("utf-8")
    config = prepare_policy(yaml.load(text, Loader=ConfigLoader), policy)
    document = yaml.compose(text, Loader=ConfigLoader)
    values = [value for key, value in document.value if key.value == "rules"]
    replacement = yaml.safe_dump(
        config["rules"], default_flow_style=True, allow_unicode=True, width=4096
    ).strip()
    # Keep every non-rule scalar byte-for-byte, including credential quoting and
    # numeric-looking passwords that different YAML loaders may interpret differently.
    if values:
        if len(values) != 1:
            raise ValueError("Duplicate rules")
        value = values[0]
        if value.start_mark.column == 0 and not value.flow_style:
            replacement = "  " + replacement
        if text[value.start_mark.index : value.end_mark.index].endswith("\n"):
            replacement += "\n"
        text = (
            text[: value.start_mark.index] + replacement + text[value.end_mark.index :]
        )
    elif document.flow_style:
        index = document.end_mark.index - 1
        text = text[:index] + ", rules: " + replacement + text[index:]
    else:
        index = document.end_mark.index
        text = text[:index] + "\nrules: " + replacement + "\n" + text[index:]
    if yaml.load(text, Loader=ConfigLoader) != config:
        raise ValueError("Cannot preserve configuration")

    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=destination.parent,
            prefix=".config-",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)
            os.fchmod(stream.fileno(), 0o600)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    try:
        if len(sys.argv) != 4:
            raise ValueError("Invalid arguments")
        prepare_file(sys.argv[1], sys.argv[2], Path(sys.argv[3]))
    except Exception:
        # YAML exceptions can contain complete input lines, including passwords.
        sys.stderr.write("Mihomo runtime policy preparation failed\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
