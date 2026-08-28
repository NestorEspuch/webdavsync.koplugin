# WebDAVSync

KOReader plugin for safely synchronizing new files from a WebDAV server
to local Kindle storage.

## Version

0.1

## Goals

- Download new files from WebDAV.
- Preserve the remote directory structure.
- Never delete local files.
- Never overwrite existing files.
- Use temporary files during downloads.
- Restrict local destinations to `/mnt/us/`.

## Current status

v0.1 is an initial development build.

The WebDAV server selection and recursive synchronization engine are
not enabled yet.
