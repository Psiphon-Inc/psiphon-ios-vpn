#!/usr/bin/env python

#
# Copyright (c) 2017, Psiphon Inc.
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import argparse
import json
import requests


def gen_release_post_body(tag_name, description, commitish='master', draft=True, prerelease=True):
    post_body = {
        "tag_name": tag_name,
        "target_commitish": commitish,
        "name": tag_name,
        "body": description,
        "draft": draft,
        "prerelease": prerelease
    }
    return post_body


def make_api_request(access_token, repo, post_body):
    url = "https://api.github.com/repos/{}?access_token={}".format(repo, access_token)
    r = requests.post(url, data=json.dumps(post_body))

    response = {
        'status_code': r.status_code,
        'reason': r.reason,
        'text': r.text
    }

    if r.status_code != requests.codes.created:
        r.raise_for_status()

    return response


def main():
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        prog="git_release",
    )

    parser.add_argument("-a",
                        "--access-token",
                        help="GitHub access token.",
                        required=True,
                        type=str)

    parser.add_argument("-r",
                        "--repo",
                        help="Specifies the target github repo. In the form :github_username/:repo_name/:branch_name. "
                             "E.g. Psiphon-Inc/psiphon-ios-vpn/releases.",
                        required=True,
                        type=str)

    parser.add_argument("-c",
                        "--commitish",
                        help="Specifies the commitish value that determines where the Git tag is created from. "
                             "Can be any branch or commit SHA. Unused if the Git tag already exists. "
                             "Default: the repository's default branch (usually master).",
                        required=True,
                        default="master",
                        type=str)

    parser.add_argument("-t",
                        "--tag-name",
                        help="Github release tag name.",
                        required=True,
                        type=str)

    parser.add_argument("-d",
                        "--description",
                        help="Github release description.",
                        required=True,
                        type=str)

    draft_parser = parser.add_mutually_exclusive_group(required=True)
    draft_parser.add_argument('--draft',
                              help='Create a draft (unpublished) release.',
                              dest='draft',
                              action='store_true')
    draft_parser.add_argument('--no-draft',
                              help='Create a published release.',
                              dest='draft',
                              action='store_false')

    prerelease_parser = parser.add_mutually_exclusive_group(required=True)
    prerelease_parser.add_argument('--release',
                                   help='Identify the release as a full release.',
                                   dest='prerelease',
                                   action='store_false')
    prerelease_parser.add_argument('--prerelease',
                                   help='Identify the release as a prerelease.',
                                   dest='prerelease',
                                   action='store_true')

    args = parser.parse_args()

    post_body = gen_release_post_body(tag_name=args.tag_name,
                                      description=args.description,
                                      commitish=args.commitish,
                                      draft=args.draft,
                                      prerelease=args.prerelease)

    print("Creating release:\n{}".format(json.dumps(post_body)))

    response = make_api_request(access_token=args.access_token, repo=args.repo, post_body=post_body)

    print("Got response:\n{}".format(response))


if __name__ == "__main__":
    main()
