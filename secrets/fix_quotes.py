import re
import sys

file_path = '/home/tippy/source/flakes/secrets/common.yaml'

inside_protected = False
protected_keys = ['ssh', 'sops']

new_lines = []
modified_count = 0

with open(file_path, 'r') as f:
    for line in f:
        # Check for top-level keys (indent 0)
        # Regex: start of line, identifier, colon.
        top_key_match = re.match(r'^([\w-]+):', line)
        if top_key_match:
            key = top_key_match.group(1)
            if key in protected_keys:
                inside_protected = True
            else:
                inside_protected = False
        
        # Only modify if not in protected block and not a comment line
        if not inside_protected and not line.strip().startswith('#'):
            # Match strictly: key: space ENC[...] space/newline
            # We explicitly check for unquoted ENC. 
            # If it's already quoted "ENC[...]", this regex won't match (no quote in pattern)
            # Pattern components:
            # 1. (\s*[-\w]+:\s+)  -> key and separator
            # 2. (ENC\[.+\])      -> The encrypted value from ENC[ to ]
            # 3. (\s*)            -> Trailing whitespace/newline
            
            m = re.match(r'^(\s*[-\w]+:\s+)(ENC\[.+\])(\s*)$', line)
            if m:
                # Reconstruct with quotes
                new_line = f'{m.group(1)}"{m.group(2)}"{m.group(3)}'
                new_lines.append(new_line)
                modified_count += 1
                continue
        
        # Keep original line if no match or protected
        new_lines.append(line)

print(f"Modifying {modified_count} lines...")

with open(file_path, 'w') as f:
    f.writelines(new_lines)
