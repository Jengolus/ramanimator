
def get_bank_pointer(bank, address):
    return (bank << 14) + (address & 0x3FFF)

def hex(num):
    return f"{num:02X}"

def decompose_address(address):
    """ Decompose into bank and address """
    return address >> 14, (address & 0x3FFF) + 0x4000

class MemoryBlock():
    """ To help me orient myself in memory """
    def __init__(self, offset, data):
        """
        Offset -- Where the slice starts
        Data -- A list of integers in unsigned byte range
        """
        self.offset = offset
        self.data = data

    def __str__(self):
        ret = f"{self.offset:0000X}: "
        for d in self.data:
            if isinstance(d, int):
                ret += f"{d:02X} "
            else:
                ret += d + " "
        return ret

    def __repr__(self):
        return str(self)

    def __getitem__(self, split):
        delta = (len(self.data) + split.start) % len(self.data)
        return MemoryBlock(self.offset + delta, self.data[split])

def find_occurrences(long_list, small_list):
    """ Find byte patterns in a memory block """
    occurrences = []
    small_length = len(small_list)

    for i in range(len(long_list) - small_length + 1):
        if long_list[i:i + small_length] == small_list:
            occurrences.append(i)

    return occurrences
