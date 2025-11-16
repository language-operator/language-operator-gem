require 'language_operator'

agent "test-agent" do
  description "Log a message to stdout as per instructions"

  task :generate_log_message do |inputs|
    { message: "Test agent is saying hello!" }
  end

  main do |inputs|
    result = execute_task(:generate_log_message)
    result
  end

  output do |outputs|
    puts outputs[:message]
  end
end
