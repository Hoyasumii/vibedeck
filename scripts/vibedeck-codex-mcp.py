"""Adapta capacidades experimentais do Codex para o SDK Swift MCP 0.12."""

import json
import subprocess
import sys


def adapt(line):
    try:
        message = json.loads(line)
        if message.get("method") != "initialize":
            return line
        capabilities = message.get("params", {}).get("capabilities", {})
        experimental = capabilities.get("experimental")
        if isinstance(experimental, dict):
            # The Swift SDK models these as strings. VibeDeck does not consume
            # experimental client capabilities; retain their JSON as text.
            capabilities["experimental"] = {
                key: value if isinstance(value, str) else json.dumps(value)
                for key, value in experimental.items()
            }
            return (json.dumps(message) + "\n").encode()
    except (ValueError, AttributeError, TypeError):
        pass
    return line


def main():
    process = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE)
    try:
        for line in sys.stdin.buffer:
            process.stdin.write(adapt(line))
            process.stdin.flush()
        process.stdin.close()
        return process.wait()
    except BrokenPipeError:
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()


if __name__ == "__main__":
    sys.exit(main())
