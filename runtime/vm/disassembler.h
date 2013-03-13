// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_DISASSEMBLER_H_
#define VM_DISASSEMBLER_H_

#include "vm/allocation.h"
#include "vm/assembler.h"
#include "vm/globals.h"

namespace dart {

// Froward declaration.
class MemoryRegion;

// Disassembly formatter interface, which consumes the
// disassembled instructions in any desired form.
class DisassemblyFormatter {
 public:
  DisassemblyFormatter() { }
  virtual ~DisassemblyFormatter() { }

  // Consume the decoded instruction at the given pc.
  virtual void ConsumeInstruction(char* hex_buffer,
                                  intptr_t hex_size,
                                  char* human_buffer,
                                  intptr_t human_size,
                                  uword pc) = 0;

  // Print a formatted message.
  virtual void Print(const char* format, ...) = 0;
};


// Basic disassembly formatter that outputs the disassembled instruction
// to stdout.
class DisassembleToStdout : public DisassemblyFormatter {
 public:
  DisassembleToStdout() : DisassemblyFormatter() { }
  ~DisassembleToStdout() { }

  virtual void ConsumeInstruction(char* hex_buffer,
                                  intptr_t hex_size,
                                  char* human_buffer,
                                  intptr_t human_size,
                                  uword pc);

  virtual void Print(const char* format, ...) PRINTF_ATTRIBUTE(2, 3);

 private:
  DISALLOW_ALLOCATION()
  DISALLOW_COPY_AND_ASSIGN(DisassembleToStdout);
};


// Disassemble instructions.
class Disassembler : public AllStatic {
 public:
  // Disassemble instructions between start and end.
  // (The assumption is that start is at a valid instruction).
  // Return true if all instructions were successfully decoded, false otherwise.
  static bool Disassemble(uword start,
                          uword end,
                          DisassemblyFormatter* formatter,
                          const Code::Comments& comments);

  static bool Disassemble(uword start,
                          uword end,
                          DisassemblyFormatter* formatter) {
    return Disassemble(start, end, formatter, Code::Comments::New(0));
  }

  static bool Disassemble(uword start,
                          uword end,
                          const Code::Comments& comments) {
    DisassembleToStdout stdout_formatter;
    return Disassemble(start, end, &stdout_formatter, comments);
  }

  static bool Disassemble(uword start, uword end) {
    DisassembleToStdout stdout_formatter;
    return Disassemble(start, end, &stdout_formatter);
  }

  // Disassemble instructions in a memory region.
  static bool DisassembleMemoryRegion(const MemoryRegion& instructions,
                                      DisassemblyFormatter* formatter) {
    uword start = instructions.start();
    uword end = instructions.end();
    return Disassemble(start, end, formatter);
  }

  static bool DisassembleMemoryRegion(const MemoryRegion& instructions) {
    uword start = instructions.start();
    uword end = instructions.end();
    return Disassemble(start, end);
  }

  // Decodes one instruction.
  // Writes a hexadecimal representation into the hex_buffer and a
  // human-readable representation into the human_buffer.
  // Writes the length of the decoded instruction in bytes in out_instr_len.
  // Returns false if the instruction could not be decoded.
  static bool DecodeInstruction(char* hex_buffer, intptr_t hex_size,
                                char* human_buffer, intptr_t human_size,
                                int *out_instr_len, uword pc);

 private:
  static const int kHexadecimalBufferSize = 32;
  static const int kUserReadableBufferSize = 256;
};

}  // namespace dart

#endif  // VM_DISASSEMBLER_H_
