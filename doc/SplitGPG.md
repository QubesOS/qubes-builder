Using Split GPG with Qubes Builder
=================================

Split GPG can be used to additionally protect your private keys. In this case
your private keys will be stored in separate VM and all operations which
require them (all signing operations) need to be configured to use
qubes-gpg-client instead of gpg directly.

This includes code signing (git tags) and package signing (rpm, deb, ...).

First you need to setup Split GPG using standard instructions. This includes
setting GPG backend VM name, for example this way:
```
echo my-gpg-backend-vm > /rw/config/gpg-split-domain
```

Signing-related options in builder.conf
---------------------------------------
### SIGN_KEY (plugin builder-fedora)
Key ID used to sign rpm packages

### DEBIAN_SIGN_KEY (plugin builder-debian)
Key ID used to sign Debian repository metadata (which contain hashes of the packages).

### GPG
Gpg binary to be used instead of `gpg`. Currently supported only by
`builder-debian` plugin.

Configuring git to use Split GPG
--------------------------------

You need to set `gpg.program` git config option to use `qubes-gpg-client-wrapper` there:
```
git --global config gpg.program qubes-gpg-client-wrapper
```

Configuring rpm --addsign to use Split GPG
---------------------------------------

You need the following lines in `~/.rpmmacros`:
```
%__gpg_sign_cmd                 /bin/sh sh -c '/usr/bin/qubes-gpg-client-wrapper \\\
        --batch --no-verbose \\\
        %{?_gpg_digest_algo:--digest-algo %{_gpg_digest_algo}} \\\
        -u "%{_gpg_name}" -sb %{__plaintext_filename} >%{__signature_filename}'
```
Above excerpt not only replaces gpg with call to qubes-gpg-client-wrapper, but
also remove some options not supported by Split GPG and change the way how
output is grabbed (shell redirection instead of -o option).

Additionally you need to set `SIGN_KEY` in builder.conf and ensure you do *not*
have `NO_SIGN=1` set.

Also note that if you use SIGN_KEY option, you do not need to set `%_gpg_name`
macro in `~/.rpmmacros`.
