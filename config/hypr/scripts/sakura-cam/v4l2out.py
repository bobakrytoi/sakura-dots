# sakura mono - sakura-cam: writes I420 frames into a v4l2loopback device ("Sakura Cam").
# The device is found by its name in /sys/class/video4linux; nothing here needs root, only the module
# (see README). The output format is set once (VIDIOC_S_FMT) and kept: frames are scaled to it upstream.
import fcntl
import os
import struct

VIDIOC_S_FMT = 0xC0D05605          # _IOWR('V', 5, struct v4l2_format), sizeof = 208 on 64-bit
VIDIOC_G_FMT = 0xC0D05604          # _IOWR('V', 4, struct v4l2_format)
V4L2_BUF_TYPE_VIDEO_OUTPUT = 2
V4L2_FIELD_NONE = 1
V4L2_COLORSPACE_REC709 = 3
YU12 = ord("Y") | ord("U") << 8 | ord("1") << 16 | ord("2") << 24


def find_device(label="Sakura Cam"):
    base = "/sys/class/video4linux"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return None
    for n in names:
        try:
            with open(os.path.join(base, n, "name")) as f:
                if f.read().strip() == label:
                    return "/dev/" + n
        except OSError:
            pass
    return None


class V4L2Out:
    def __init__(self):
        self.fd = None
        self.dev = None
        self.size = None
        self.error = ""

    def open(self, w, h, readers=None):
        """(Re)open the device for w x h. Returns True when frames can be written.
        readers(): True while another app has the device open. Then the size it already has is kept, whatever
        w x h say: v4l2loopback accepts a new format from a fresh writer even with a reader streaming, and that
        reader then gets frames of the wrong size (green garbage in Discord)."""
        if self.fd is not None and self.size == (w, h):
            return True
        if self.fd is not None:
            # new size on the open device: only while no app reads it; else keep the old size
            if readers is not None and readers(self.dev):
                return False
            if self._fmt(self.fd, w, h) is None:
                self.size = (w, h)
                return True
            return False
        dev = find_device()
        if not dev:
            self.error = "missing"
            return False
        try:
            fd = os.open(dev, os.O_WRONLY | os.O_NONBLOCK)
        except OSError as e:
            self.error = "open: " + e.strerror
            return False
        if readers is not None:
            cur = self._get(fd)
            if cur and cur != (w, h) and readers(dev):
                w, h = cur
        err = self._fmt(fd, w, h)
        if err is not None:
            os.close(fd)
            self.error = err
            return False
        self.fd, self.dev, self.size, self.error = fd, dev, (w, h), ""
        return True

    @staticmethod
    def _get(fd):
        fmt = bytearray(208)
        struct.pack_into("I", fmt, 0, V4L2_BUF_TYPE_VIDEO_OUTPUT)
        try:
            fcntl.ioctl(fd, VIDIOC_G_FMT, fmt)
        except OSError:
            return None
        w, h = struct.unpack_from("II", fmt, 8)
        return (w, h) if w and h else None

    @staticmethod
    def _fmt(fd, w, h):
        fmt = bytearray(208)
        struct.pack_into("I", fmt, 0, V4L2_BUF_TYPE_VIDEO_OUTPUT)
        # struct v4l2_pix_format at offset 8 (the union is 8-aligned)
        struct.pack_into("IIIIIIII", fmt, 8, w, h, YU12, V4L2_FIELD_NONE, w, w * h * 3 // 2,
                         V4L2_COLORSPACE_REC709, 0)
        try:
            fcntl.ioctl(fd, VIDIOC_S_FMT, fmt)
            return None
        except OSError as e:
            # EBUSY: a reader holds the device at another size (v4l2loopback keeps the format while open)
            return "busy" if e.errno == 16 else "format: " + e.strerror

    def write(self, data):
        if self.fd is None:
            return False
        try:
            os.write(self.fd, data)
            return True
        except BlockingIOError:
            return True          # nobody reading fast enough: drop this frame
        except OSError as e:
            self.error = "write: " + e.strerror
            self.close()
            return False

    def close(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
        self.fd = None
        self.size = None
