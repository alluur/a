"""Shared helpers of the asm library generators: assemble snippets with llvm-mc and format them as asm blocks."""
import subprocess, tempfile, os

def assemble(triple, attrs, text):
    with tempfile.TemporaryDirectory() as d:
        s = os.path.join(d, 'a.s'); o = os.path.join(d, 'a.o'); b = os.path.join(d, 'a.bin')
        open(s, 'w').write(text + '\n')
        cmd = ['llvm-mc', '-filetype=obj', '-triple=' + triple] + (['-mattr=' + attrs] if attrs else []) + [s, '-o', o]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode:
            raise SystemExit('assembling failed: %s\n%s\n%s' % (triple, text, r.stderr))
        subprocess.check_call(['llvm-objcopy', '-O', 'binary', '--only-section=.text', o, b])
        return open(b, 'rb').read()

def block(arch, data):
    if arch == 'x64':
        return 'x64: ' + ', '.join('0x%02X' % c for c in data) + ';'
    assert len(data) % 4 == 0
    words = ['0x%08X' % int.from_bytes(data[i:i+4], 'little') for i in range(0, len(data), 4)]
    return arch + ': ' + ', '.join(words) + ';'

CPUS = [('x64', 'x86_64', ''), ('arm64', 'aarch64', ''), ('riscv64', 'riscv64', '+a,+m,+zihintpause'), ('loongarch64', 'loongarch64', '')]

def asm_block(snips, operands):
    out = ['asm(%s) {' % operands]
    for arch, triple, attrs in CPUS:
        out.append('        ' + block(arch, assemble(triple, attrs, snips[arch])))
    out.append('    }')
    return '\n'.join(out)

