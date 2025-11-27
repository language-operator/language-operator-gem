require 'language_operator'

agent "s001" do
  description "Log a message continuously"

  task :generate_message,
    instructions: "Generate a short message to log to stdout",
    inputs: {},
    outputs: { message: 'string' }

  task :log_message,
    instructions: "Output the message to stdout as a log entry",
    inputs: { message: 'string' },
    outputs: { success: 'boolean' }

  main do |inputs|
    message_data = execute_task(:generate_message)
    execute_task(:log_message, inputs: message_data)
    message_data
  end

  constraints do
    max_iterations 999999
    timeout "10m"
  end

  output do |outputs|
    puts outputs[:message]
  end
end
