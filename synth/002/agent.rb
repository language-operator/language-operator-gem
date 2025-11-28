require 'language_operator'

agent "s002" do
  description "Tell me a fortune every 10 minutes"

  mode :scheduled
  schedule "*/10 * * * *"

  task :generate_fortune,
    instructions: "Generate a short, positive fortune message. Keep it under 100 words. Make it inspiring and uplifting.",
    inputs: {},
    outputs: { fortune: 'string' }

  task :format_output,
    instructions: "Format the fortune message into a readable output string with a title 'Your Fortune:'",
    inputs: { fortune: 'string' },
    outputs: { message: 'string' }

  main do |inputs|
    fortune = execute_task(:generate_fortune)
    output = execute_task(:format_output, inputs: fortune)
    output
  end

  constraints do
    max_iterations 999999
    timeout "10m"
  end

  output do |outputs|
    puts outputs[:message]
  end
end
