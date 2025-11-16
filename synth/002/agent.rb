require 'language_operator'

agent "test-agent" do
  description "Tell a fortune every 10 minutes"
  mode :scheduled
  schedule "*/10 * * * *"

  task :generate_fortune,
    instructions: "Generate a random fortune for the user",
    inputs: {},
    outputs: { fortune: 'string' }

  main do |inputs|
    fortune_data = execute_task(:generate_fortune)
    { fortune: fortune_data[:fortune] }
  end

  output do |outputs|
    puts outputs[:fortune]
  end
end
