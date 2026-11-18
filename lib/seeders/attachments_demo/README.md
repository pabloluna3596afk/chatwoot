# Local attachment review data

Run from the checkout mounted into your development container:

```sh
docker exec preview-rails bundle exec rails dev:attachments_demo
docker exec -e ACCOUNT_ID=2 preview-rails bundle exec rails dev:attachments_demo
docker exec -e ACCOUNT_ID=1 -e RESET=1 preview-rails bundle exec rails dev:attachments_demo
```

The account must already exist. Production aborts. Install ImageMagick (`convert`
and `identify`) in the development container and make `spec/assets/attachments_demo`
available there along with `lib/seeders/attachments_demo*` and the Rake task.
No additional gems or provider credentials are required.

The task creates eight `Adjuntos demo · …` inboxes and contacts, with one
conversation each. It prints conversation URLs and scenario → message IDs.
Rerunning preserves IDs and counts. `RESET=1` replaces only messages with this
seed's source IDs in its marked conversations; it keeps the inboxes, contacts,
conversation identities and any manually added messages. It never deletes the
account. The per-account lock serializes concurrent invocations.

These are synthetic channel scenarios, including combinations a provider may
not accept when sending. Do not send from these inboxes: credentials are fake.
Inserts bypass model callbacks, so there are no delivery, subscription,
automation, broadcast or indexing jobs. Stored files use the local Disk service
(`test` in tests), even when the installation uses remote storage. Blobs include
dimensions and analyzed metadata, so attachment creation queues no analysis jobs.

Images in PNG/JPEG/GIF/WebP, extreme dimensions, grids of 2/3/4/6/7 images,
three-page PDFs (small and over 5 MiB), valid minimal DOCX/XLSX/ZIP, TXT,
audio/voice/video, stickers, location, contacts, replies, private notes, failed
delivery and unavailable external media are included. Instagram adds story
mention/reel cases. External media uses a deliberately absent same-origin path
`/dashboard/images/attachments-demo-expired-404.png`; no third-party 404 service
or expiring credentials are needed. Image failures are deterministic; loading
and transport errors can be reviewed later with network throttling.

The email case mirrors the mailbox pipeline: its original MIME has a CID image
and three files, its rendered HTML references the locally stored inline image,
and its attachment list contains only the three regular files. The original
MIME is saved in `additional_attributes.attachments_demo_mime` for inspection.

For later visual PRs, use the printed URLs at desktop and 390 px, in light and
dark themes; compare the same scenario IDs before and after. Check receipt
legibility, extreme dimensions, grid navigation, full filenames, PDF page
navigation, reply targets, private-note color and failed/expired states. This
task itself changes no UI.

## Small fixture sources

Each fixture is under 200 KB. `photo.jpg` is a resized crop of the repository's
`app/javascript/dashboard/assets/images/auth/signup-bg.jpg`. `receipt.png` is a
synthetic receipt rendered with ImageMagick and DejaVu Sans. The audio samples
are two-second synthetic sine waves (440 Hz MP3 / 660 Hz Ogg Opus). The portrait
video is a two-second FFmpeg test pattern at 180×320, 10 fps, H.264/yuv420p.
FFmpeg/fonts are only needed to regenerate those fixtures. Image variants,
documents and archives are generated at task runtime in a temporary directory.
