class ApplicationService
  def self.call(*args, &block)
    new(*args, &block).call
  end

  # Optional: Override this to define a custom error handler in subclasses
  def handle_error(error)
    raise error
  end
end
