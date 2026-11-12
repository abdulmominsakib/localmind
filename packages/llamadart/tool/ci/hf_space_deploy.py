#!/usr/bin/env python3
"""Upload a folder to a Hugging Face static Space, creating it only if missing.

Hugging Face applies a separate quota to Space creation, even with exist_ok.
Probe existing Spaces first so regular uploads avoid that creation endpoint.
Only HTTP 429 is retried, with at most MAX_ATTEMPTS tries per call and one
MAX_TOTAL_WAIT budget shared by probe, create and upload. A numeric Retry-After
is honored; an HTTP-date, negative or missing value falls back to jittered
exponential backoff. 401, 403, validation and every other error fail at once so
a broken deploy stays visible.
"""
import argparse
import os
import random
import sys
import time

MAX_ATTEMPTS = 5
MAX_TOTAL_WAIT = 240.0
MAX_BACKOFF = 30.0
BASE_BACKOFF = 5.0


def status_of(error):
    return getattr(getattr(error, 'response', None), 'status_code', None)


def retry_after(error):
    value = getattr(getattr(error, 'response', None), 'headers', {}).get('Retry-After')
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return None
    return seconds if seconds >= 0 else None


class Budget:
    waited = 0.0


def with_retry(label, call, budget, sleep=time.sleep, jitter=random.random, log=print):
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            return call()
        except Exception as error:
            if status_of(error) != 429 or attempt == MAX_ATTEMPTS:
                raise
            delay = retry_after(error)
            if delay is None:
                delay = min(MAX_BACKOFF, BASE_BACKOFF * 2 ** (attempt - 1)) * (0.5 + jitter() / 2)
            if budget.waited + delay > MAX_TOTAL_WAIT:
                raise
            log(f'{label}: HTTP 429 on attempt {attempt}/{MAX_ATTEMPTS}; retrying in {delay:.0f}s',
                file=sys.stderr)
            sleep(delay)
            budget.waited += delay


def deploy(api, repo, folder, commit_message, delete_patterns, public, **retry_options):
    budget = Budget()
    try:
        with_retry('repo_info', budget=budget, call=lambda: api.repo_info(
            repo_id=repo, repo_type='space'), **retry_options)
    except Exception as error:
        if status_of(error) != 404:
            raise
        create_options = {'private': False} if public else {}
        with_retry('create_repo', budget=budget, call=lambda: api.create_repo(
            repo_id=repo, repo_type='space', space_sdk='static', exist_ok=True, **create_options),
            **retry_options)
    with_retry('upload_folder', budget=budget, call=lambda: api.upload_folder(
        repo_id=repo, repo_type='space', folder_path=folder, revision='main',
        delete_patterns=delete_patterns, commit_message=commit_message),
        **retry_options)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--folder', required=True)
    parser.add_argument('--commit-message', required=True)
    parser.add_argument('--delete-pattern', action='append', required=True)
    parser.add_argument('--public', action='store_true')
    args = parser.parse_args(argv)

    from huggingface_hub import HfApi

    deploy(HfApi(token=os.environ['HF_TOKEN']), args.repo, args.folder, args.commit_message,
           args.delete_pattern, args.public)


if __name__ == '__main__':
    main()
