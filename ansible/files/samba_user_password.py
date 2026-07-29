#!/usr/bin/env python3
"""Create or reset a Samba AD user without exposing the password in argv."""

import argparse
import os
import re

import ldb
from samba.auth import system_session
from samba.param import LoadParm
from samba.samdb import SamDB


USERNAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("create", "reset"))
    parser.add_argument("--username", required=True)
    parser.add_argument("--given-name")
    parser.add_argument("--surname")
    parser.add_argument("--email")
    parser.add_argument("--must-change", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if not USERNAME_PATTERN.fullmatch(args.username):
        raise SystemExit("Invalid AD username")

    password = os.environ.pop("AD_USER_PASSWORD", "")
    if not password:
        raise SystemExit("AD_USER_PASSWORD is required")

    loadparm = LoadParm()
    loadparm.load_default()
    samdb = SamDB(session_info=system_session(), lp=loadparm)

    if args.operation == "create":
        if not all((args.given_name, args.surname, args.email)):
            raise SystemExit("Create requires given name, surname, and email")
        samdb.newuser(
            args.username,
            password,
            force_password_change_at_next_login_req=args.must_change,
            givenname=args.given_name,
            surname=args.surname,
            mailaddress=args.email,
        )
        print(f"User '{args.username}' added successfully")
        return

    user_filter = (
        "(&(objectClass=user)(sAMAccountName=%s))"
        % ldb.binary_encode(args.username)
    )
    samdb.setpassword(
        user_filter,
        password,
        force_change_at_next_login=args.must_change,
        username=args.username,
    )
    print("Changed password OK")


if __name__ == "__main__":
    main()
