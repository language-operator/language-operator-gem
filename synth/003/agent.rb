require 'language_operator'

agent "synth-003" do
  description "Build a story one sentence at a time, adding exactly one new sentence every hour"
  mode :scheduled
  schedule "0 * * * *"

  task :read_existing_story,
    instructions: "Read the story.txt file from workspace. If it doesn't exist, return empty string for content and 0 for sentence count. Return the content and number of sentences (count newlines as sentence separators).",
    inputs: {},
    outputs: { content: 'string', sentence_count: 'integer' }

  task :generate_next_sentence,
    instructions: "Generate exactly one new sentence to continue this story. Maintain consistent tone and style from the existing content. Only output the new sentence without any additional text or formatting.",
    inputs: { existing_content: 'string' },
    outputs: { sentence: 'string' }

  task :append_to_story,
    instructions: "Append the new sentence to story.txt in workspace. If the file has existing content, add a newline before appending. Return whether the operation succeeded and the new total sentence count (counting existing sentences plus one).",
    inputs: { sentence: 'string' },
    outputs: { success: 'boolean', total_sentences: 'integer' }

  main do |inputs|
    story_data = execute_task(:read_existing_story)
    new_sentence = execute_task(:generate_next_sentence, inputs: { existing_content: story_data[:content] })
    result = execute_task(:append_to_story, inputs: { sentence: new_sentence[:sentence] })
    { added_sentence: new_sentence[:sentence], total_sentences: result[:total_sentences] }
  end

  constraints do
    max_iterations 999999
    timeout "10m"
  end

  output do |outputs|
    puts "Added sentence: #{outputs[:added_sentence]}"
    puts "Story now has #{outputs[:total_sentences]} sentences"
  end
end
