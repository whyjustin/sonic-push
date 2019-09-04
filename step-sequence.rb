require 'thread'

class StepSequence
  def initialize
    @step_semaphore = Mutex.new
    @steps = Array.new
  end

  def add_step(step)
    @step_semaphore.synchronize do
      @steps.push(step)
    end
  end

  def remove_step(index)
    @step_semaphore.synchronize do
      @steps.delete_at(index)
    end
  end

  def get_step(index)
    @step_semaphore.synchronize do
      return @steps[index]
    end
  end

  def length
    return @steps.length
  end
end

class Step
  def initialize(note)
    @note = note
    @step_semaphore = Mutex.new
    @step = nil
  end

  def note
    return @note
  end

  def step=step
    @step_semaphore.synchronize do
      @step = step
    end
  end

  def step
    return @step
  end
end
