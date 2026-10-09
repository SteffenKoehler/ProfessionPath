# Minimal reader for WDBC files (WoW 3.3.5a client tables).
import struct


class DBC:
    def __init__(self, path):
        with open(path, "rb") as f:
            data = f.read()
        magic, self.records, self.fields, self.size, strsize = struct.unpack_from("<4s4I", data, 0)
        if magic != b"WDBC":
            raise ValueError("not a WDBC file: " + path)
        self.data = data
        self.base = 20
        self.strings = 20 + self.records * self.size
        self.ints = "<%di" % self.fields
        self.uints = "<%dI" % self.fields
        self.floats = "<%df" % self.fields

    def rows(self, signed=False):
        fmt = self.ints if signed else self.uints
        for i in range(self.records):
            yield struct.unpack_from(fmt, self.data, self.base + i * self.size)

    def float_row(self, index):
        return struct.unpack_from(self.floats, self.data, self.base + index * self.size)

    def string(self, offset):
        start = self.strings + offset
        end = self.data.index(b"\0", start)
        return self.data[start:end].decode("utf-8", "replace")
