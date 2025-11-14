# frozen_string_literal: true

require 'language_operator'

agent 'hello-world' do
  description 'Logs a message to stdout'

  objectives [
    "Log the message 'Hello, world!' to agent logs"
  ]

  workflow do
    step :log_message do
      execute do |_results, _context|
        puts 'Hello, world!'
        { result: 'message logged' }
      end
    end
  end

  constraints do
    max_iterations 999_999
    timeout '10m'
  end

  output do
    workspace 'results/output.txt'
  end
end
