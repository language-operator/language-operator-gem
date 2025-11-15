# frozen_string_literal: true

require 'language_operator'

agent 'hello-world' do
  description 'Logs a message to stdout'

  task :log_message,
       instructions: "log the message 'Hello, world!' to agent logs",
       inputs: {},
       outputs: { result: 'string' }

  main do |_inputs|
    puts 'Hello, world!'
    { result: 'message logged' }
  end

  constraints do
    max_iterations 999_999
    timeout '10m'
  end

  output do
    workspace 'results/output.txt'
  end
end
