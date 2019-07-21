Color = Struct.new(:red, :green, :blue)

class PadColorPallete
  def self.black
    return Color.new(0, 0, 0)
  end

  def self.grey
    return Color.new(100, 100, 100)
  end

  def self.blue
    return Color.new(0, 0, 255)
  end
  
  def self.green
    return Color.new(0, 255, 0)
  end
    
  def self.red
    return Color.new(255, 0, 0)
  end

  def self.teal
    return Color.new(0, 255, 255)
  end

  def self.yellow
    return Color.new(255, 255, 0)
  end

  def self.magenta
    return Color.new(255, 0, 255)
  end

  def self.lime
    return Color.new(128, 255, 128)
  end

  def self.violet
    return Color.new(128, 128, 255)
  end
end

class SecondStripColorPallete
  def self.black
    return 0
  end

  def self.orange
    return 10
  end

  def self.orange_blink_fast
    return 12
  end

  def self.red
    return 5
  end
end

class NoteColorPallete
  def self.off 
    return 0
  end

  def self.dim
    return 1
  end

  def self.lit
    return 4
  end
end
