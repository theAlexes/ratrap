ratrap — blocklisting http stub
-------------------------------------------------------------------------------
%%VERSION%%

ratrap is TODO

ratrap is distributed under the ISC license.

Homepage: https://fossil.se30.xyz/ratrap  

## Installation

ratrap can be installed with `opam`:

    opam install ratrap

If you don't use `opam` consult the [`opam`](opam) file for build
instructions.

## Documentation

The documentation and API reference is generated from the source
interfaces. It can be consulted [online][doc] or via `odig doc
ratrap`.

[doc]: https://fossil.se30.xyz/ratrap

## Sample programs

If you installed ratrap with `opam` sample programs are located in
the directory `opam var ratrap:doc`.

In the distribution sample programs and tests are located in the
[`test`](test) directory. They can be built and run
with:

    topkg build --tests true && topkg test 
