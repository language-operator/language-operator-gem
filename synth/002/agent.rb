require 'language_operator'

agent "test-agent" do
  description "Tell a fortune every 10 minutes"
  mode :scheduled
  schedule "*/10 * * * *"

  task :tell_fortune,
    instructions: "Generate a random fortune message",
    inputs: {},
    outputs: { fortune: 'string' }

  main do |inputs|
    execute_task(:tell_fortune)
  end

  output do |outputs|
    puts outputs[:fortune]
  end
end
