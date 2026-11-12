#!/usr/bin/env python3
"""Compare thin little-endian arm64 dylib section/UUID identity, not runtime identity.

Format basis: Apple xnu EXTERNAL_HEADERS/mach-o/loader.h (mach_header_64,
segment_command_64, section_64, uuid_command and load-command structures).
https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h

Only S_ZEROFILL=1, S_GB_ZEROFILL=12 and S_THREAD_LOCAL_ZEROFILL=18 lack
file-backed content. Empty sections have no bytes to hash but retain metadata.
Unknown commands are refused rather than silently interpreted. Equality here
does not establish DYLD mapping, exports, dependencies or signature validity.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

MAGIC = 0xFEEDFACF
ARM64 = 0x0100000C
ZEROFILL = {1: "S_ZEROFILL", 12: "S_GB_ZEROFILL", 18: "S_THREAD_LOCAL_ZEROFILL"}
DYLIB_COMMANDS = {0xC, 0xD, 0x80000018, 0x8000001F, 0x20, 0x80000023}
STRING_COMMANDS = {0xE, 0xF, 0x8000001C, 0x27}
LINKEDIT_COMMANDS = {0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E, 0x80000033, 0x80000034}


class InvalidMachO(ValueError):
    """Input is malformed or outside this deliberately narrow format scope."""


def require(condition, message):
    if not condition:
        raise InvalidMachO(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def bounded(offset, size, limit, label):
    require(0 <= offset <= limit and 0 <= size <= limit - offset,
            f"{label}: range outside bounds")


def fixed_name(raw):
    name, separator, padding = raw.partition(b"\0")
    require(not separator or not any(padding), "nonzero fixed-name padding")
    require(bool(name), "empty segment/section name")
    try:
        return name.decode("ascii")
    except UnicodeDecodeError as exc:
        raise InvalidMachO("non-ASCII segment/section name unsupported") from exc


def command_string(command, offset, minimum):
    require(minimum <= offset < len(command), "load-command string offset invalid")
    end = command.find(b"\0", offset)
    require(end >= 0, "unterminated load-command string")
    require(not any(command[end + 1:]), "nonzero load-command string padding")
    try:
        return command[offset:end].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise InvalidMachO("non-UTF8 load-command string") from exc


def parse(data):
    """Parse only caller-supplied bytes; never executes or loads the image."""
    require(len(data) >= 32, "truncated mach_header_64")
    h = struct.unpack_from("<8I", data)
    magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = h
    require(magic == MAGIC, "unsupported magic: require thin Mach-O 64 little-endian")
    require(cpu == ARM64, "unsupported CPU: require arm64")
    require(filetype == 6, "unsupported filetype: require MH_DYLIB")
    require(reserved == 0, "nonzero reserved header field")
    bounded(32, sizeofcmds, len(data), "load-command region")
    require(ncmds > 0 and ncmds <= sizeofcmds // 8, "invalid load-command count")
    end_commands = 32 + sizeofcmds
    commands, sections, dependencies, payloads = [], [], [], []
    segment_names, section_names, singleton_commands = set(), set(), set()
    file_ranges, segment_ranges, segment_vm_ranges, section_vm_ranges = [], [], [], []
    uuid = None
    cursor = 32

    def external(offset, size, label):
        bounded(offset, size, len(data), label)
        if size:
            require(offset >= end_commands, f"{label}: overlaps load commands")
        payloads.append({"label": label, "offset": offset, "size": size,
                         "sha256": digest(data[offset:offset + size])})

    for index in range(ncmds):
        bounded(cursor, 8, end_commands, "load-command header")
        cmd, size = struct.unpack_from("<2I", data, cursor)
        require(size >= 8 and size % 8 == 0, "invalid 64-bit load-command size/alignment")
        bounded(cursor, size, end_commands, "load command")
        command = data[cursor:cursor + size]
        record = {"cmd": cmd, "cmdsize": size, "sha256": digest(command)}
        if cmd not in DYLIB_COMMANDS | STRING_COMMANDS | {0x19}:
            require(cmd not in singleton_commands, f"duplicate singleton command {cmd:#x}")
            singleton_commands.add(cmd)

        if cmd == 0x19:  # LC_SEGMENT_64
            require(size >= 72, "truncated segment_command_64")
            values = struct.unpack_from("<II16sQQQQiiII", command)
            _, _, raw_name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, count, segflags = values
            name = fixed_name(raw_name)
            require(name not in segment_names, "duplicate segment name")
            segment_names.add(name)
            require(size == 72 + count * 80, "segment section count/size mismatch")
            bounded(fileoff, filesize, len(data), "segment file range")
            bounded(vmaddr, vmsize, 1 << 64, "segment VM range")
            require(filesize <= vmsize, "segment file size exceeds VM size")
            if vmsize:
                for start, stop in segment_vm_ranges:
                    require(vmaddr + vmsize <= start or vmaddr >= stop,
                            "overlapping segment VM ranges")
                segment_vm_ranges.append((vmaddr, vmaddr + vmsize))
            if filesize:
                for start, stop in segment_ranges:
                    require(fileoff + filesize <= start or fileoff >= stop,
                            "overlapping segment file ranges")
                segment_ranges.append((fileoff, fileoff + filesize))
            record["segment"] = {"name": name, "vmaddr": vmaddr, "vmsize": vmsize,
                "fileoff": fileoff, "filesize": filesize, "maxprot": maxprot,
                "initprot": initprot, "flags": segflags, "nsects": count}
            for number in range(count):
                section_raw = command[72 + number * 80:152 + number * 80]
                sv = struct.unpack("<16s16sQQ8I", section_raw)
                sn, sg, addr, length, offset, align, reloff, nreloc, sf, r1, r2, r3 = sv
                sn, sg = fixed_name(sn), fixed_name(sg)
                require(sg == name, "section segment-name mismatch")
                require((sg, sn) not in section_names, "duplicate section identity")
                section_names.add((sg, sn))
                bounded(addr - vmaddr, length, vmsize, "section VM range")
                if length:
                    for start, stop in section_vm_ranges:
                        require(addr + length <= start or addr >= stop,
                                "overlapping section VM ranges")
                    section_vm_ranges.append((addr, addr + length))
                require(align <= 63, "unsupported section alignment exponent")
                require(not length or addr % (1 << align) == 0, "misaligned section address")
                if nreloc:
                    external(reloff, nreloc * 8, f"relocations:{sg}/{sn}")
                else:
                    require(reloff == 0, "relocation offset without relocation entries")
                section_type = sf & 0xFF
                backed = section_type not in ZEROFILL
                section = {"segment": sg, "section": sn, "addr": addr,
                    "size": length, "offset": offset, "align": align,
                    "reloff": reloff, "nreloc": nreloc, "flags": sf,
                    "reserved1": r1, "reserved2": r2, "reserved3": r3,
                    "file_backed": backed}
                if backed:
                    bounded(offset, length, len(data), "section file range")
                    bounded(offset - fileoff, length, filesize, "section within segment")
                    if length:
                        require(addr - vmaddr == offset - fileoff,
                                "section VM/file mapping disagrees with segment")
                        require(offset >= end_commands, "section overlaps load commands")
                        require(offset % (1 << align) == 0, "misaligned section file offset")
                        for start, stop in file_ranges:
                            require(offset + length <= start or offset >= stop,
                                    "overlapping file-backed sections")
                        file_ranges.append((offset, offset + length))
                        section["sha256"] = digest(data[offset:offset + length])
                    else:
                        section["skip_reason"] = "empty section; metadata compared"
                else:
                    section["skip_reason"] = ZEROFILL[section_type]
                sections.append(section)
        elif cmd == 0x1B:  # LC_UUID
            require(size == 24 and uuid is None, "invalid or duplicate LC_UUID")
            uuid = command[8:24].hex()
        elif cmd in DYLIB_COMMANDS:
            require(size >= 24, "truncated dylib_command")
            nameoff, timestamp, current, compatibility = struct.unpack_from("<4I", command, 8)
            dependency = {"cmd": cmd, "name": command_string(command, nameoff, 24),
                          "timestamp": timestamp, "current_version": current,
                          "compatibility_version": compatibility}
            require(not any(d["cmd"] == cmd and
                            (cmd == 0xD or d["name"] == dependency["name"])
                            for d in dependencies), "duplicate dylib identity/dependency")
            dependencies.append(dependency)
            record["dylib"] = dependency
        elif cmd in STRING_COMMANDS:
            require(size >= 16, "truncated string command")
            record["string"] = command_string(command, struct.unpack_from("<I", command, 8)[0], 12)
        elif cmd in LINKEDIT_COMMANDS:
            require(size == 16, "invalid linkedit_data_command")
            offset, length = struct.unpack_from("<2I", command, 8)
            external(offset, length, f"command:{cmd:#x}")
        elif cmd in {0x22, 0x80000022}:  # LC_DYLD_INFO[_ONLY]
            require(size == 48, "invalid dyld_info_command")
            values = struct.unpack_from("<10I", command, 8)
            for name, offset, length in zip(("rebase", "bind", "weak_bind", "lazy_bind", "export"), values[::2], values[1::2]):
                external(offset, length, f"dyld_info:{name}")
        elif cmd == 2:  # LC_SYMTAB; nlist_64 is 16 bytes
            require(size == 24, "invalid symtab_command")
            offset, count, strings, stringsize = struct.unpack_from("<4I", command, 8)
            external(offset, count * 16, "symbol table")
            external(strings, stringsize, "string table")
        elif cmd == 0xB:  # LC_DYSYMTAB
            require(size == 80, "invalid dysymtab_command")
            values = struct.unpack_from("<18I", command, 8)
            for i, width, label in ((6, 8, "toc"), (8, 56, "module table"),
                                    (10, 4, "external references"), (12, 4, "indirect symbols"),
                                    (14, 8, "external relocations"), (16, 8, "local relocations")):
                external(values[i], values[i + 1] * width, label)
        elif cmd == 0x32:  # LC_BUILD_VERSION
            require(size >= 24, "truncated build_version_command")
            count = struct.unpack_from("<I", command, 20)[0]
            require(size == 24 + count * 8, "invalid build-version tool count")
        elif cmd in {0x24, 0x25, 0x2F, 0x30, 0x2A}:
            require(size == 16, "invalid version command")
        elif cmd == 0x1A:  # LC_ROUTINES_64
            require(size == 72, "invalid routines_command_64")
        else:
            raise InvalidMachO(f"unsupported load command {cmd:#x}; review support before use")
        require(record not in commands, "duplicate load command")
        commands.append(record)
        cursor += size
    require(cursor == end_commands, "load commands do not exhaust sizeofcmds")
    require(uuid is not None, "missing LC_UUID")
    require(any(s["file_backed"] and s["size"] for s in sections),
            "no nonempty file-backed sections")
    return {"file_bytes": len(data), "whole_file_sha256": digest(data),
        "header_identity": {"cputype": cpu, "cpusubtype": subtype,
                            "filetype": filetype, "flags": flags, "reserved": reserved},
        "uuid": uuid, "section_count": len(sections),
        "nonempty_file_backed_section_count": sum(s["file_backed"] and s["size"] > 0 for s in sections),
        "zerofill_section_count": sum(not s["file_backed"] for s in sections),
        "sections": sections, "load_commands": commands,
        "dylib_commands": dependencies, "referenced_payloads": payloads}


def compare(left_bytes, right_bytes):
    left, right = parse(left_bytes), parse(right_bytes)
    metadata_equal = left["sections"] == right["sections"]
    # Direct byte equality supplements the per-section digests, including order.
    bytes_equal = len(left["sections"]) == len(right["sections"]) and all(
        a["file_backed"] == b["file_backed"] and a["size"] == b["size"] and
        (not a["file_backed"] or left_bytes[a["offset"]:a["offset"] + a["size"]] ==
         right_bytes[b["offset"]:b["offset"] + b["size"]])
        for a, b in zip(left["sections"], right["sections"]))
    checks = {"header_identity_equal": left["header_identity"] == right["header_identity"],
              "uuid_equal": left["uuid"] == right["uuid"],
              "ordered_section_metadata_and_hashes_equal": metadata_equal,
              "section_bytes_equal": bytes_equal}
    command_differences = []
    for i in range(max(len(left["load_commands"]), len(right["load_commands"]))):
        a = left["load_commands"][i] if i < len(left["load_commands"]) else None
        b = right["load_commands"][i] if i < len(right["load_commands"]) else None
        if a != b:
            command_differences.append({"index": i, "left": a, "right": b})
    return {"schema_version": 1, "scope": "thin little-endian arm64 MH_DYLIB",
        "code_data_uuid_identity": all(checks.values()), "checks": checks,
        "whole_file_identity": left_bytes == right_bytes,
        "load_commands_equal": left["load_commands"] == right["load_commands"],
        "load_command_differences": command_differences,
        "dylib_commands_equal": left["dylib_commands"] == right["dylib_commands"],
        "referenced_payloads_equal": left["referenced_payloads"] == right["referenced_payloads"],
        "runtime_identity_proven": False,
        "transformation_cause": "Unattributed; no signature-only claim is made.",
        "limitations": "Requires separate actual DYLD single-image mapping proof, exports/dependency checks and review of all command/payload differences. Does not validate code signatures or dynamic behavior.",
        "left": left, "right": right}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    args = parser.parse_args()
    try:
        result = compare(args.left.read_bytes(), args.right.read_bytes())
    except (InvalidMachO, OSError) as exc:
        print(json.dumps({"schema_version": 1, "code_data_uuid_identity": False,
                          "runtime_identity_proven": False, "error": str(exc)}, indent=2))
        return 2
    result["left"]["path"] = str(args.left)
    result["right"]["path"] = str(args.right)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["code_data_uuid_identity"] else 1


if __name__ == "__main__":
    sys.exit(main())
