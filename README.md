# zfetch

[![Linux Workflow Status](https://img.shields.io/github/workflow/status/truemedian/zfetch/Linux?label=Linux&style=for-the-badge)](https://github.com/truemedian/zfetch/actions/workflows/linux.yml)
[![Windows Workflow Status](https://img.shields.io/github/workflow/status/truemedian/zfetch/Windows?label=Windows&style=for-the-badge)](https://github.com/truemedian/zfetch/actions/workflows/windows.yml)
[![MacOS Workflow Status](https://img.shields.io/github/workflow/status/truemedian/zfetch/MacOS?label=MacOS&style=for-the-badge)](https://github.com/truemedian/zfetch/actions/workflows/macos.yml)

A HTTP request library for Zig with HTTPS support.

## Features

* HTTPS support, including trust handling (provided by [iguanaTLS](https://github.com/alexnask/iguanaTLS))
* A relatively simple interface.

## Notes

* Passing `null` as the `trust_chain` in Request.init will tell zfetch to **not check server certificates**. If you do
  not trust your connection, please provide a iguanaTLS x509 trust chain.
* zfetch only does rudimentary checks to ensure functions are called in the right order. These are nowhere near enough
  to prevent you from doing so, please call the functions in the order they are intended to be called in.

## Examples

see [examples](https://github.com/truemedian/zfetch/tree/master/examples).

**More Coming Soon...?**
