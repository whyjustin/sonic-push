Color = Struct.new(:red, :green, :blue)

class PadColorPallete
  def self.black
    return Color.new(0, 0, 0)
  end
  
  def self.green
    return Color.new(0, 255, 0)
  end
  
  
  def self.red
    return Color.new(255, 0, 0)
  end
end

class SecondStripColorPallete
  def self.black
    return 0
  end
  
  def self.red
    return 5
  end
end
