class Quirks

  def self.load_from_file(filename = 'config/quirks.yml')
    File.open(Rails.root.join(filename), 'r') do |f|
      y = YAML.load(f.read)
      y.each do |key, value|
        y[key] = value.collect{|s|
          # Serializing regular expressions is gross, so let's just look for
          # strings that look like regexps and leave everything else alone.
          if s =~ /^\/.*\/$/
            Regexp.new(s[1..-2])
          else
            s
          end
        }
      end

      y.default_proc = Proc.new {[]}

      y
    end
  end

  def self.defined_quirks
    Quirks::THE_QUIRKS.keys
  end

  def self.[](a)
    Quirks::THE_QUIRKS[a]
  end

  Quirks.send(:remove_const, :THE_QUIRKS) if Quirks.const_defined? :THE_QUIRKS
  Quirks.const_set(:THE_QUIRKS, Quirks.load_from_file)

end
