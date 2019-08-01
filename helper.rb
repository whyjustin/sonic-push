class Helper
  def self.within(number, min, max)
    return [max, [min, number].max].min
  end
end
