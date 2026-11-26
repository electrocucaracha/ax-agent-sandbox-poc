#!/usr/bin/env -S uv --quiet run --script
"""Manage team-demo issues through the host-side git server API.

Env: GIT_API (https://localhost:8443/api/v1), GIT_USER, GIT_PASS.
  epic <repo> <file>   create the epic issue from a Markdown file (title = first heading)
  list <repo>          print "number|role" for every issue titled "[role:<name>] ..."
  body <repo> <n>      print the title and body of an issue
  fallback <repo>      create the role issues from a fixed plan (used when the triage agent made none)
"""

# /// script
# requires-python = ">=3.10"
# dependencies = ["click>=8.1"]
# ///

import base64
import json
import logging
import re
import ssl
import urllib.error
import urllib.request
from pathlib import Path

import click

CA_FILE = Path(__file__).resolve().parents[1] / "certs" / "ca.crt"
log = logging.getLogger("issues")

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


def tls_context():
    """Verify the server chain against the demo CA.

    The port-forwarded host (localhost) differs from the certificate's SAN, so
    only the hostname check is disabled; the chain must still be signed by the CA.
    """
    context = ssl.create_default_context(cafile=str(CA_FILE))
    context.check_hostname = False
    return context


def call(settings, method, path, data=None):
    """Call the demo git API; errors report only the HTTP status, never credentials."""
    auth = (
        "Basic "
        + base64.b64encode(
            f"{settings['user']}:{settings['password']}".encode()
        ).decode()
    )
    req = urllib.request.Request(
        settings["api"] + path,
        method=method,
        headers={"Authorization": auth, "Content-Type": "application/json"},
        data=json.dumps(data).encode() if data is not None else None,
    )
    log.debug("%s %s", method, path)
    try:
        with urllib.request.urlopen(req, context=tls_context()) as r:
            return json.load(r)
    except urllib.error.HTTPError as error:
        raise click.ClickException(
            f"{method} {path} failed: HTTP {error.code}"
        ) from None


def open_issues(settings, repo):
    """Return open non-PR issues ordered by their numeric identifier."""
    return sorted(
        call(
            settings,
            "GET",
            f"/repos/{repo}/issues?type=issues&state=open&limit=50",
        ),
        key=lambda i: i["number"],
    )


@click.group()
@click.option("--api", envvar="GIT_API", required=True, help="Git API base URL.")
@click.option("--user", envvar="GIT_USER", required=True, help="API user name.")
@click.option("--password", envvar="GIT_PASS", required=True, help="API password.")
@click.option("-v", "--verbose", is_flag=True, help="Log each API request.")
@click.pass_context
def cli(ctx, api, user, password, verbose):
    """Manage team-demo issues through the host-side git server API."""
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )
    ctx.obj = {"api": api, "user": user, "password": password}


@cli.command()
@click.argument("repo")
@click.argument("file", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.pass_obj
def epic(settings, repo, file):
    """Create the epic issue from a Markdown file (title = first heading)."""
    text = file.read_text()
    title = re.sub(r"^#\s*", "", text.splitlines()[0])
    number = call(
        settings, "POST", f"/repos/{repo}/issues", {"title": title, "body": text}
    )["number"]
    log.info("Created epic issue #%s in %s", number, repo)
    click.echo(number)


@cli.command("list")
@click.argument("repo")
@click.pass_obj
def list_roles(settings, repo):
    """Print number|role for every issue titled "[role:<name>] ..."."""
    for issue in open_issues(settings, repo):
        match = re.match(r"\[role:([a-z-]+)\]", issue["title"])
        if match:
            click.echo(f"{issue['number']}|{match.group(1)}")


@cli.command()
@click.argument("repo")
@click.argument("number", type=int)
@click.pass_obj
def body(settings, repo, number):
    """Print the title and body of an issue."""
    issue = call(settings, "GET", f"/repos/{repo}/issues/{number}")
    click.echo(f"# {issue['title']}\n\n{issue['body']}")


@cli.command()
@click.argument("repo")
@click.pass_obj
def fallback(settings, repo):
    """Create the role issues from the fixed plan."""
    for role, title in PLAN.items():
        message = f"Assignment for the `{role}` role. Scope and acceptance criteria are in the epic (issue #1) and your role rules."
        call(
            settings,
            "POST",
            f"/repos/{repo}/issues",
            {"title": f"[role:{role}] {title}", "body": message},
        )
        log.info("Created role issue for %s", role)


if __name__ == "__main__":
    cli()
