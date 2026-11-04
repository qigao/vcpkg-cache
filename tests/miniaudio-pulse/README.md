# miniaudio 0.11.22#1 candidate qualification

The port retains upstream 0.11.22, its archive SHA512 and Unlicense OR MIT-0 licensing.
Only two failed-initialization paths gain pa_context_unref before mainloop destruction.
The public failure remains MA_NO_BACKEND (-203). No backend is disabled and no fallback
or LSan suppression is used. Products still own a single implementation translation unit.

The workflow tests actual libpulse against an invalid address (synchronous connect failure)
and an absent Unix socket (asynchronous connection wait failure). Log assertions require
32 visits to the intended branch. It compares known original and patched header SHA256s,
requires the original leak, and requires clean patched ASan/UBSan/LSan process exit.
An unsuccessfully initialized context must not be passed to ma_context_uninit.

This is dependency failure-lifecycle qualification, not an installer/consumer probe.
Successful daemon/device start-stop, original Media sanitizer/TSan suites, iOS static
linking, physical-device permissions and redistributable dependency closure remain
separate gates. No package release or downstream lock change is performed by this PR.
The two negative scenarios alone do not establish complete provider qualification.
