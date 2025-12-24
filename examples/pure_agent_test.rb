# Pure Agent Definition (no Ruby setup code)
# This demonstrates that agents automatically get chat endpoints by default

agent "test-basic" do
  description "Simple test agent to verify default chat endpoints"
  mode :autonomous

  # Simple task
  task :do_work,
    instructions: "Perform some basic work",
    inputs: {},
    outputs: { 
      message: 'string',
      timestamp: 'string'
    }

  main do |inputs|
    work_result = execute_task(:do_work)
    work_result
  end

  constraints do
    max_iterations 5  # Just run a few times for testing
    timeout '10s'
  end
end