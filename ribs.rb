require 'optparse'

Record = Struct.new(
  :offset,
  :data
)

RLE_Record = Struct.new(
  :offset,
  :rle_size,
  :value
)

class InvalidPatch < StandardError
end

class Patch
  attr_reader :records

  def initialize(opts)
    @records = []

    parse(opts.patch)
    output_records if opts.verbose
    apply(opts.base, opts.out) if opts.out
  end

  private

  def validate(patch)
    # Minimal patch validation
    raise InvalidPatch, 'Invalid patch size' if patch.size < 14
    raise InvalidPatch, 'Missing PATCH header' if patch[0..4] != 'PATCH'
    raise InvalidPatch, 'Missing EOF footer' if patch[-3..-1] != 'EOF'
  end

  def parse(patch_file)
    patch = read(patch_file)
    validate(patch)

    patch = patch[5..-1]

    until patch.size <= 3
      offset = slice_get_uint24(patch)
      size = slice_get_uint16(patch)
      add_record(patch, offset, size) # altera patch fora do metodo :(
    end
  end

  def add_record(patch, offset, size)
    if size.zero?
      add_rle_record(patch, offset)
    else
      add_normal_record(patch, offset, size)
    end
  end

  def add_rle_record(patch, offset)
    rle_size = slice_get_uint16(patch)
    rle_value = patch.slice!(0)
    @records << RLE_Record.new(offset, rle_size, rle_value)
  end

  def add_normal_record(patch, offset, size)
    data = patch.slice!(0...size)
    @records << Record.new(offset, data)
  end

  def output_records
    @records.each_with_index { |rec, i| print_record_info(rec, i) }
  end

  def print_record_info(rec, off)
    if rec.is_a? Record
      puts "Record No.: #{off + 1}, Type: Normal, " \
           "Offset: #{rec.offset.to_s(16)}, Bytes: #{rec.data.size}"
    else
      puts "Record No.: #{off + 1}, Type: RLE,    " \
           "Offset: #{rec.offset.to_s(16)}, " \
           "Repeat: #{rec.rle_size}, Value: #{rec.value.dump}"
    end
  end

  def apply(base_rom, output)
    base = read(base_rom)
    @records.each { |rec| write_record(rec, base) }
    write(output, base)
  end

  def write_record(rec, data)
    if rec.is_a? Record
      data[rec.offset...rec.offset + rec.data.size] = rec.data
    else
      data[rec.offset...rec.offset + rec.rle_size] = rec.value * rec.rle_size
    end
  end

  def slice_get_uint16(str)
    str.slice!(0..1).unpack1('S>').to_i
  end

  def slice_get_uint24(str)
    a, b, c = str.slice!(0..2).bytes
    (a << 16) | (b << 8) | c
  end

  def write(file, data)
    IO.binwrite(file, data)
  end

  def read(file)
    IO.binread(file)
  end
end

Options = Struct.new(
  :patch,
  :base,
  :out,
  :verbose
)

class Parser
  def self.parse(options)
    args = Options.new

    opt_parser = OptionParser.new do |opts|
      opts.banner = 'ribs is a basic IPS patcher. Because we needed one more.' \
                    "\nUsage: ruby #{$PROGRAM_NAME} -b ROM -p IPS -o OUTPUT ..."

      opts.on('-bROM', '--base ROM', 'Base ROM') do |n|
        args.base = n
      end

      opts.on('-pIPS', '--patch IPS', 'IPS patch to apply') do |n|
        args.patch = n
      end

      opts.on('-oOUTPUT', '--out OUTPUT', 'Patched ROM to output') do |n|
        args.out = n
      end

      opts.on_tail('-v', '--verbose', 'Run verbosely') do |n|
        args.verbose = n
      end

      opts.on_tail('-h', '--help', 'Display this help and exit') do
        puts opts
        exit
      end
    end

    begin
      opt_parser.parse!(options)
    rescue OptionParser::InvalidOption => e
      puts e
      puts opt_parser
      exit
    end

    if (args.base && args.patch).nil?
      puts opt_parser
      exit
    end

    args
  end
end

options = Parser.parse(ARGV)
Patch.new(options)
