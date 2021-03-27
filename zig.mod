id: ejw82j2ipa0eul25ohgdh6yy5nkrtn2pf0rq18m0079w6wj7
name: zfetch
main: src/main.zig
dependencies:
  - type: git
    path: https://github.com/truemedian/hzzp

  - type: git
    path: https://github.com/alexnask/iguanaTLS
    name: iguanaTLS
    main: src/main.zig

  - type: git
    path: https://github.com/MasterQ32/zig-network
    name: network
    main: network.zig

  - type: git
    path: https://github.com/MasterQ32/zig-uri
    name: uri
    main: uri.zig
