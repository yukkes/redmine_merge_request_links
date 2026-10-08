#!/usr/bin/env python3
"""Reproduce the screenshot evidence in this directory.

For each Redmine version, this script starts a Redmine container with the
plugin mounted, creates one issue per platform (GitHub, GitLab, Gitea,
CodeCommit), links an open, a merged and a closed merge request to each
issue through signed webhooks, and takes screenshots with Playwright:

  redmine-<version>_issue_<platform>.png    issue page with 3 merge requests
  redmine-<version>_issue_list.png          issue list with merge request column

The screenshots are reduced to a 256 color palette. The script also checks
the merge request filter for each state and exits with a non-zero status
if a page does not show the expected content.

Requirements: Docker, Python 3.9+, `pip install playwright pillow` and
`playwright install chromium` (or pass --chrome-path). Chromium keeps its
temporary profile in $TMPDIR; point it to a disk directory if /tmp is a
small tmpfs.

Usage (from the repository root):

  evidence/take_screenshots.py --build             # build images and run
  evidence/take_screenshots.py --versions 7.0      # reuse built images
"""

import argparse
import hashlib
import hmac
import http
import json
import pathlib
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMAGE = "redmine_merge_request_links_test"
SECRET_KEY_BASE = "evidence-secret-key-base-0123456789"
TOKENS = {
    "github": "gh-secret",
    "gitlab": "gl-secret",
    "gitea": "gt-secret",
    "codecommit": "cc-secret",
}
PLATFORMS = ["GitHub", "GitLab", "Gitea", "CodeCommit"]
STATES = ["open", "merged", "closed"]
ADMIN_PASSWORD = "admin12345"

SUPPORTED_VERSIONS = ["5.0", "5.1", "6.0", "6.1", "7.0"]

SEED_SCRIPT = f"""
Setting.default_language = 'en'
Redmine::DefaultData::Loader.load('en') unless Tracker.exists?
admin = User.find_by_login('admin')
admin.password = admin.password_confirmation = '{ADMIN_PASSWORD}'
admin.must_change_passwd = false
admin.save!
project = Project.find_by_identifier('demo') ||
  Project.create!(name: 'Demo', identifier: 'demo', is_public: true,
                  enabled_module_names: %w[issue_tracking merge_request_links],
                  trackers: Tracker.all)
%w[{" ".join(PLATFORMS)}].each do |platform|
  subject = "#{{platform}} merge requests"
  issue = Issue.find_by_subject(subject)
  unless issue
    issue = Issue.create!(project: project, tracker: project.trackers.first,
                          author: admin, subject: subject)
    issue.journals.create!(user: admin, notes: 'A note in the issue history.')
  end
  puts "ISSUE #{{platform}} #{{issue.id}}"
end
"""


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def image_tag(version):
    return f"{IMAGE}:{version}"


def build_image(version):
    print(f"[{version}] building image", flush=True)
    result = subprocess.run(
        [
            "docker",
            "build",
            "-t",
            image_tag(version),
            "--build-arg",
            f"REDMINE_VERSION={version}",
            str(ROOT),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        result.check_returncode()


def container_name(version, theme=None):
    name = f"mrl_evidence_{version}"
    if theme:
        name += f"_{theme.name}"
    return name


def start_container(version, port, theme=None):
    name = container_name(version, theme)
    subprocess.run(["docker", "rm", "-f", name], capture_output=True, check=False)
    args = [
        "docker",
        "run",
        "-d",
        "--name",
        name,
        "-p",
        f"{port}:3000",
        "-e",
        "REDMINE_PLUGINS_MIGRATE=1",
        "-e",
        f"REDMINE_SECRET_KEY_BASE={SECRET_KEY_BASE}",
        "-e",
        f"REDMINE_MERGE_REQUEST_LINKS_GITHUB_WEBHOOK_TOKEN={TOKENS['github']}",
        "-e",
        f"REDMINE_MERGE_REQUEST_LINKS_GITLAB_WEBHOOK_TOKEN={TOKENS['gitlab']}",
        "-e",
        f"REDMINE_MERGE_REQUEST_LINKS_GITEA_WEBHOOK_TOKEN={TOKENS['gitea']}",
        "-e",
        f"REDMINE_MERGE_REQUEST_LINKS_CODECOMMIT_WEBHOOK_TOKEN={TOKENS['codecommit']}",
        "-v",
        f"{ROOT}:/usr/src/redmine/plugins/redmine_merge_request_links:ro",
    ]
    if theme:
        theme_dir = pathlib.Path(theme).resolve()
        args += [
            "-v",
            f"{theme_dir}:/usr/src/redmine/themes/{theme_dir.name}:ro",
        ]
    args += [image_tag(version)]
    run(*args, stdout=subprocess.DEVNULL)


def wait_for_http(base, timeout=600):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(base, timeout=5)
            return
        except (urllib.error.URLError, ConnectionError, OSError):
            time.sleep(3)
    raise TimeoutError(f"{base} did not respond within {timeout}s")


def seed(version, theme=None):
    script = SEED_SCRIPT
    if theme:
        script += f"Setting.ui_theme = '{theme.name}'\n"
    result = run(
        "docker",
        "exec",
        "-i",
        "-e",
        f"SECRET_KEY_BASE={SECRET_KEY_BASE}",
        "-e",
        "RAILS_ENV=production",
        container_name(version, theme),
        "bash",
        "-c",
        "cd /usr/src/redmine && cat > /tmp/seed.rb && bin/rails runner /tmp/seed.rb",
        input=script,
        capture_output=True,
        text=True,
    )
    issues = {}
    for line in result.stdout.splitlines():
        if line.startswith("ISSUE "):
            _, platform, issue_id = line.split()
            issues[platform] = int(issue_id)
    return issues


def webhook_request(platform, state, issue_id, number):
    """Return headers and JSON body of a webhook event as sent by the platform."""
    title = f"{platform} {state} example"
    if platform == "GitLab":
        # GitLab reports open merge requests as "opened"
        gitlab_state = "opened" if state == "open" else state
        body = {
            "object_kind": "merge_request",
            "user": {"username": "jdoe"},
            "object_attributes": {
                "iid": number,
                "state": gitlab_state,
                "title": title,
                "url": f"https://gitlab.example.com/group/app/-/merge_requests/{number}",
                "description": f"Refs #{issue_id}",
                "target": {"path_with_namespace": "group/app"},
            },
        }
        payload = json.dumps(body).encode()
        return {"X-Gitlab-Event": "Merge Request Hook", "X-Gitlab-Token": TOKENS["gitlab"]}, payload

    if platform == "CodeCommit":
        # The EventBridge event as relayed by an API destination or Lambda
        status = "Open" if state == "open" else "Closed"
        body = {
            "version": "0",
            "id": f"00000000-0000-0000-0000-{number:012d}",
            "detail-type": "CodeCommit Pull Request State Change",
            "source": "aws.codecommit",
            "account": "123456789012",
            "time": "2026-01-01T00:00:00Z",
            "region": "ap-northeast-1",
            "resources": [],
            "detail": {
                "pullRequestId": str(number),
                "pullRequestStatus": status,
                "isMerged": "True" if state == "merged" else "False",
                "repositoryNames": ["app"],
                "title": title,
                "description": f"Refs #{issue_id}",
                "author": "arn:aws:iam::123456789012:user/jdoe",
                "callerUserArn": "arn:aws:iam::123456789012:user/jdoe",
            },
        }
        payload = json.dumps(body).encode()
        return {"X-CodeCommit-Token": TOKENS["codecommit"]}, payload

    # GitHub and Gitea report merged pull requests as closed + merged
    pr_state = "open" if state == "open" else "closed"
    if platform == "GitHub":
        url, login, repo = f"https://github.com/example/app/pull/{number}", "octocat", "example/app"
    else:
        url, login, repo = (
            f"https://gitea.example.com/org/app/pulls/{number}",
            "gitea-user",
            "org/app",
        )
    body = {
        "pull_request": {
            "number": number,
            "state": pr_state,
            "merged": state == "merged",
            "html_url": url,
            "title": title,
            "body": f"Refs #{issue_id}",
            "user": {"login": login},
            "base": {"repo": {"full_name": repo}},
        }
    }
    payload = json.dumps(body).encode()
    if platform == "GitHub":
        signature = hmac.new(TOKENS["github"].encode(), payload, hashlib.sha1).hexdigest()
        return {"X-GitHub-Event": "pull_request", "X-Hub-Signature": f"sha1={signature}"}, payload
    signature = hmac.new(TOKENS["gitea"].encode(), payload, hashlib.sha256).hexdigest()
    return {"X-Gitea-Event": "pull_request", "X-Gitea-Signature": signature}, payload


def send_webhooks(base, issues):
    number = 10
    for platform in PLATFORMS:
        for state in STATES:
            number += 1
            headers, payload = webhook_request(platform, state, issues[platform], number)
            request = urllib.request.Request(
                f"{base}/merge_requests/event",
                data=payload,
                method="POST",
                headers={"Content-Type": "application/json", **headers},
            )
            with urllib.request.urlopen(request) as response:
                if response.status != http.HTTPStatus.OK:
                    raise RuntimeError(f"{platform}/{state}: HTTP {response.status}")


def take_screenshots(playwright, base, issues, out_prefix, chrome_path):
    errors = []
    browser = playwright.chromium.launch(executable_path=chrome_path)
    page = browser.new_page(viewport={"width": 1280, "height": 900})

    def shot(name):
        page.wait_for_load_state("networkidle")
        # Keep the cursor away from the content to avoid hover effects
        page.mouse.move(1279, 899)
        page.screenshot(path=f"{out_prefix}_{name}.png", full_page=True)

    page.goto(f"{base}/login")
    page.fill("#username", "admin")
    page.fill("#password", ADMIN_PASSWORD)
    with page.expect_navigation():
        page.click("#login-submit")

    for platform in PLATFORMS:
        page.goto(f"{base}/issues/{issues[platform]}")
        rows = page.locator("#issue-merge-requests .merge-request").evaluate_all("""
          els => Promise.all(els.map(async e => {
            const m = getComputedStyle(e).backgroundImage.match(/url\\("?(.*?)"?\\)/);
            return {
              state: e.querySelector('.merge-request-state').innerText.trim(),
              provider: e.className.split(' ')[1].replace('merge-request-', ''),
              icon: m ? (await fetch(m[1])).ok : false
            };
          }))""")
        print(f"  issue {platform}: {rows}", flush=True)
        if [r["state"] for r in rows] != STATES:
            errors.append(f"{platform}: states {[r['state'] for r in rows]}")
        if any(r["provider"] != platform.lower() or not r["icon"] for r in rows):
            errors.append(f"{platform}: provider class or icon missing")
        # The box is rendered inside the history container.
        if not page.evaluate("""() => {
              const box = document.getElementById('issue-merge-requests');
              return box.parentElement.id === 'history';
            }"""):
            errors.append(f"{platform}: box not inside history")
        overlapping = page.evaluate("""() => {
              const box = document.getElementById('issue-merge-requests').getBoundingClientRect();
              return [...document.querySelectorAll('#history *')].filter(el => {
                if (el.closest('#issue-merge-requests')) return false;
                const style = getComputedStyle(el);
                const painted = ['Top', 'Bottom', 'Left', 'Right'].some(side =>
                  parseFloat(style[`border${side}Width`]) > 0 && style[`border${side}Style`] !== 'none'
                ) || style.backgroundColor !== 'rgba(0, 0, 0, 0)';
                // Tabs are clipped by their container.
                const rect = el.getBoundingClientRect();
                const right = Math.min(rect.right, (el.closest('.tabs') || el).getBoundingClientRect().right);
                return painted && rect.width > 0 && right > box.left + 1 && rect.left < box.right &&
                  rect.bottom > box.top && rect.top < box.bottom;
              }).map(el => `${el.tagName}.${el.className}`);
            }""")
        if overlapping:
            errors.append(f"{platform}: history overlaps box: {overlapping}")
        shot(f"issue_{platform.lower()}")

    columns = "c[]=subject&c[]=merge_requests&sort=id"
    page.goto(f"{base}/projects/demo/issues?set_filter=1&{columns}&f[]=status_id&op[status_id]=*")
    shot("issue_list")
    for state in STATES:
        page.goto(
            f"{base}/projects/demo/issues?set_filter=1&{columns}"
            f"&f[]=merge_request&op[merge_request]=%3D&v[merge_request][]={state}"
        )
        subjects = page.locator("tr.issue td.subject").all_inner_texts()
        print(f"  filter {state}: {subjects}", flush=True)
        if subjects != [f"{p} merge requests" for p in PLATFORMS]:
            errors.append(f"filter {state}: {subjects}")

    browser.close()
    return errors


def reduce_colors(path):
    with Image.open(path) as image:
        reduced = image.convert("RGB").quantize(256, dither=Image.Dither.NONE)
    reduced.save(path, optimize=True)


def run_version(version, port, out_dir, chrome_path, failures, lock, theme=None):
    base = f"http://localhost:{port}"
    try:
        print(f"[{version}] starting Redmine on {base}", flush=True)
        start_container(version, port, theme)
        wait_for_http(base)
        issues = seed(version, theme)
        send_webhooks(base, issues)
        print(f"[{version}] taking screenshots", flush=True)
        prefix = out_dir / f"redmine-{version}"
        if theme:
            prefix = out_dir / f"redmine-{version}-{theme.name}"
        with sync_playwright() as playwright:
            errors = take_screenshots(
                playwright, base, issues, str(prefix), chrome_path
            )
        with lock:
            failures.extend([f"{version} {error}" for error in errors])
        for path in sorted(out_dir.glob(f"redmine-{version}_*.png")):
            reduce_colors(path)
        if theme:
            for path in sorted(out_dir.glob(f"redmine-{version}-{theme.name}_*.png")):
                reduce_colors(path)
    finally:
        subprocess.run(
            ["docker", "rm", "-f", container_name(version, theme)],
            capture_output=True,
            check=False,
        )


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--versions", nargs="+", default=SUPPORTED_VERSIONS, choices=SUPPORTED_VERSIONS
    )
    parser.add_argument("--build", action="store_true", help="build the test images first")
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent)
    parser.add_argument(
        "--chrome-path", help="Chromium executable to use instead of the bundled one"
    )
    parser.add_argument("--base-port", type=int, default=3100)
    parser.add_argument(
        "--parallel", action="store_true",
        help="run all versions in parallel instead of sequentially",
    )
    parser.add_argument(
        "--theme", type=pathlib.Path,
        help="path to a theme directory to mount and select in Redmine",
    )
    args = parser.parse_args()

    if args.build:
        for version in args.versions:
            build_image(version)

    failures = []
    lock = threading.Lock()

    if args.parallel and len(args.versions) > 1:
        threads = []
        for index, version in enumerate(args.versions):
            port = args.base_port + index
            thread = threading.Thread(
                target=run_version,
                args=(version, port, args.out, args.chrome_path, failures, lock, args.theme),
            )
            threads.append(thread)
            thread.start()
        for thread in threads:
            thread.join()
    else:
        for index, version in enumerate(args.versions):
            port = args.base_port + index
            run_version(version, port, args.out, args.chrome_path, failures, lock, args.theme)

    if failures:
        print("FAILED:\n  " + "\n  ".join(failures))
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
