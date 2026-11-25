#!/usr/bin/env python3
"""Issue helper for the team demo, run on the host against the git server API.
Env: GIT_API (https://localhost:8443/api/v1), GIT_USER, GIT_PASS.
  epic <repo> <file>   create the epic issue from a Markdown file (title = first heading)
  list <repo>          print "number|role" for every issue titled "[role:<name>] ..."
  body <repo> <n>      print the title and body of an issue
  fallback <repo>      create the role issues from a fixed plan (used when the triage agent made none)
"""
import base64, json, os, re, ssl, sys, urllib.request

API = os.environ["GIT_API"]
AUTH = "Basic " + base64.b64encode(f"{os.environ['GIT_USER']}:{os.environ['GIT_PASS']}".encode()).decode()
CTX = ssl._create_unverified_context()

# The fixed plan mirrors what the triage agent is asked to produce.
PLAN = {
    "developer": "Refactor value resolution into ordered sources and add click.config_option()",
    "quality": "Unit and functional tests for every requirement",
    "mutation": "Mutation testing of the new code and tests that kill the survivors",
    "docs": "Documentation, changelog and examples for config files",
    "ux": "Review help text, error messages and the --config option for usability",
    "sre": "Operability: failure modes, logging and a rollback note",
    "product-owner": "Acceptance criteria and sign-off checklist for the epic",
    "principal": "Design review of the pull requests",
    "security": "Security review of file loading and parsing",
    "performance": "Performance review: import time and resolution overhead stay within the gate",
}


def call(method, path, data=None):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": AUTH, "Content-Type": "application/json"},
                                 data=json.dumps(data).encode() if data is not None else None)
    with urllib.request.urlopen(req, context=CTX) as r:
        return json.load(r)


def issues(repo):
    return sorted(call("GET", f"/repos/{repo}/issues?type=issues&state=open&limit=50"), key=lambda i: i["number"])


cmd, repo = sys.argv[1], sys.argv[2]
if cmd == "epic":
    text = open(sys.argv[3]).read()
    title = re.sub(r"^#\s*", "", text.splitlines()[0])
    print(call("POST", f"/repos/{repo}/issues", {"title": title, "body": text})["number"])
elif cmd == "list":
    for i in issues(repo):
        m = re.match(r"\[role:([a-z-]+)\]", i["title"])
        if m:
            print(f"{i['number']}|{m.group(1)}")
elif cmd == "body":
    i = call("GET", f"/repos/{repo}/issues/{sys.argv[3]}")
    print(f"# {i['title']}\n\n{i['body']}")
elif cmd == "fallback":
    for role, title in PLAN.items():
        body = f"Assignment for the `{role}` role. Scope and acceptance criteria are in the epic (issue #1) and your role rules."
        call("POST", f"/repos/{repo}/issues", {"title": f"[role:{role}] {title}", "body": body})
