# frozen_string_literal: true

require 'language_operator'

agent 'test-agent' do
  description 'Log a message to stdout as per instructions'

  task :generate_log_message do |_inputs|
    { message: 'Test agent is saying hello!' }
  end

  main do |_inputs|
    result = execute_task(:generate_log_message)
    result
  end

  output do |outputs|
    puts outputs[:message]
  end
end
