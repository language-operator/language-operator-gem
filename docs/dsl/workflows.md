# Workflow Guide

Complete guide to defining workflows in the Language Operator agent DSL.

## Table of Contents

- [Overview](#overview)
- [Workflow Definition](#workflow-definition)
- [Step Types](#step-types)
- [Step Dependencies](#step-dependencies)
- [Parameter Passing](#parameter-passing)
- [Error Handling](#error-handling)
- [Complete Examples](#complete-examples)

## Overview

Workflows define step-by-step execution plans for agents. Each step can:
- Call external tools
- Execute LLM prompts
- Run custom code
- Depend on previous steps
- Pass data between steps

## Workflow Definition

Define a workflow inside an agent block:

```ruby
agent "workflow-agent" do
  workflow do
    step :step_name do
      # Step configuration
    end
  end
end
```

## Step Types

### Tool Invocation Steps

Execute external tools (MCP servers, APIs, etc.):

```ruby
workflow do
  step :fetch_data do
    tool 'database_query'
    params(
      query: 'SELECT * FROM users WHERE active = true',
      database: 'production'
    )
  end
end
```

**Components:**
- `tool` (String): Name of the tool to invoke
- `params` (Hash): Parameters to pass to the tool

### Prompt/LLM Steps

Execute LLM prompts for analysis, generation, or decision-making:

```ruby
workflow do
  step :analyze do
    prompt "Analyze this data and identify trends: {previous_step.output}"
  end
end
```

**Components:**
- `prompt` (String): The prompt to send to the LLM
- Supports parameter interpolation from previous steps

### Custom Execution Steps

Run custom Ruby code:

```ruby
workflow do
  step :process do
    execute do |context|
      # Custom logic
      data = context[:previous_step_output]
      result = data.map { |item| item['value'] * 2 }
      { processed_data: result }
    end
  end
end
```

**Components:**
- `execute` (Block): Custom Ruby code to execute
- Block receives `context` hash with previous step outputs
- Return value becomes this step's output

### Conditional Steps

Execute steps based on conditions:

```ruby
workflow do
  step :check_status do
    tool 'health_check'
  end

  step :alert_if_down do
    depends_on :check_status
    condition do |context|
      context[:check_status][:status] != 'healthy'
    end

    tool 'send_alert'
    params(
      message: 'System is down!',
      severity: 'critical'
    )
  end
end
```

## Step Dependencies

### Simple Dependencies

Steps can depend on previous steps:

```ruby
workflow do
  step :first do
    tool 'fetch_data'
  end

  step :second do
    depends_on :first
    prompt "Process: {first.output}"
  end
end
```

**Execution order:**
1. `:first` executes
2. `:second` waits for `:first` to complete
3. `:second` accesses `:first` output via interpolation

### Multiple Dependencies

Steps can depend on multiple previous steps:

```ruby
workflow do
  step :fetch_users do
    tool 'database_query'
    params query: 'SELECT * FROM users'
  end

  step :fetch_orders do
    tool 'database_query'
    params query: 'SELECT * FROM orders'
  end

  step :merge_data do
    depends_on [:fetch_users, :fetch_orders]
    execute do |context|
      users = context[:fetch_users][:output]
      orders = context[:fetch_orders][:output]
      # Merge logic...
    end
  end
end
```

**Parallel Execution:**
- `:fetch_users` and `:fetch_orders` execute in parallel
- `:merge_data` waits for both to complete

### Dependency Chains

Build complex workflows with chains of dependencies:

```ruby
workflow do
  step :extract do
    tool 'web_scraper'
    params url: 'https://api.example.com/data'
  end

  step :transform do
    depends_on :extract
    execute do |context|
      # Transform data
    end
  end

  step :load do
    depends_on :transform
    tool 'database_insert'
    params(
      table: 'processed_data',
      data: '{transform.output}'
    )
  end

  step :notify do
    depends_on :load
    tool 'send_email'
    params(
      to: 'team@company.com',
      subject: 'ETL Complete',
      body: 'Processed {extract.count} records'
    )
  end
end
```

## Parameter Passing

### Output Interpolation

Access previous step outputs using `{step_name.field}` syntax:

```ruby
workflow do
  step :get_user do
    tool 'database_query'
    params query: 'SELECT * FROM users WHERE id = 123'
  end

  step :send_email do
    depends_on :get_user
    tool 'email_send'
    params(
      to: '{get_user.email}',        # Access nested field
      subject: 'Hello {get_user.name}',
      body: 'Your account is active'
    )
  end
end
```

### Entire Output Passing

Pass the entire output of a previous step:

```ruby
workflow do
  step :fetch_data do
    tool 'api_call'
  end

  step :analyze do
    depends_on :fetch_data
    prompt "Analyze this complete dataset: {fetch_data.output}"
  end
end
```

### Context Access in Custom Steps

Access all previous outputs in custom execution blocks:

```ruby
workflow do
  step :step1 do
    tool 'fetch_data'
  end

  step :step2 do
    tool 'fetch_more_data'
  end

  step :combine do
    depends_on [:step1, :step2]
    execute do |context|
      data1 = context[:step1][:output]
      data2 = context[:step2][:output]

      combined = {
        total_records: data1.length + data2.length,
        merged: data1 + data2
      }

      combined
    end
  end
end
```

### Default Values

Provide defaults for missing data:

```ruby
workflow do
  step :get_config do
    tool 'read_config'
  end

  step :process do
    depends_on :get_config
    execute do |context|
      timeout = context.dig(:get_config, :timeout) || 30
      max_retries = context.dig(:get_config, :retries) || 3

      # Use config values with defaults
    end
  end
end
```

## Error Handling

### Retry on Failure

Configure automatic retries for steps:

```ruby
workflow do
  step :unreliable_api_call do
    tool 'external_api'
    params endpoint: '/data'

    retry_on_failure max_attempts: 3, backoff: :exponential
  end
end
```

### Error Handling Blocks

Define custom error handling:

```ruby
workflow do
  step :risky_operation do
    tool 'flaky_service'
    params action: 'process'

    on_error do |error, context|
      # Log error
      puts "Step failed: #{error.message}"

      # Return fallback value
      { status: 'failed', fallback_data: [] }
    end
  end
end
```

### Continue on Failure

Allow workflow to continue even if a step fails:

```ruby
workflow do
  step :optional_enrichment do
    tool 'enrichment_service'
    params data: '{previous.output}'

    continue_on_failure true
  end

  step :main_process do
    depends_on :optional_enrichment
    execute do |context|
      # Check if enrichment succeeded
      if context[:optional_enrichment][:error]
        # Process without enrichment
      else
        # Process with enrichment
      end
    end
  end
end
```

### Timeout Handling

Set timeouts for individual steps:

```ruby
workflow do
  step :slow_operation do
    tool 'long_running_task'
    timeout '5m'  # 5 minutes

    on_timeout do
      { status: 'timeout', partial_results: [] }
    end
  end
end
```

## Complete Examples

### ETL Pipeline

```ruby
agent "data-etl-pipeline" do
  description "Extract, transform, and load data daily"

  mode :scheduled
  schedule "0 2 * * *"  # 2 AM daily

  workflow do
    # Extract
    step :extract_source1 do
      tool 'database_query'
      params(
        connection: 'source_db_1',
        query: 'SELECT * FROM orders WHERE updated_at >= CURRENT_DATE - INTERVAL \'1 day\''
      )
    end

    step :extract_source2 do
      tool 'api_call'
      params(
        url: 'https://api.partner.com/orders',
        params: { since: '24h' }
      )
    end

    # Transform
    step :transform_and_merge do
      depends_on [:extract_source1, :extract_source2]

      execute do |context|
        source1_data = context[:extract_source1][:output]
        source2_data = context[:extract_source2][:output]

        # Normalize and merge
        merged = []
        source1_data.each do |record|
          merged << {
            id: record['order_id'],
            amount: record['total_amount'],
            source: 'db1'
          }
        end

        source2_data.each do |record|
          merged << {
            id: record['id'],
            amount: record['amount'],
            source: 'api'
          }
        end

        { records: merged, count: merged.length }
      end
    end

    # Load
    step :load_warehouse do
      depends_on :transform_and_merge

      tool 'database_bulk_insert'
      params(
        connection: 'warehouse',
        table: 'orders_unified',
        data: '{transform_and_merge.records}'
      )

      retry_on_failure max_attempts: 3
    end

    # Verify
    step :verify_load do
      depends_on :load_warehouse

      tool 'database_query'
      params(
        connection: 'warehouse',
        query: 'SELECT COUNT(*) as loaded_count FROM orders_unified WHERE loaded_at >= CURRENT_DATE'
      )
    end

    # Notify
    step :send_completion_email do
      depends_on [:transform_and_merge, :verify_load]

      tool 'send_email'
      params(
        to: 'data-team@company.com',
        subject: 'ETL Pipeline Complete',
        body: 'Processed {transform_and_merge.count} records. Warehouse now has {verify_load.loaded_count} records for today.'
      )
    end
  end

  constraints do
    timeout '30m'
    daily_budget 1000  # $10
  end
end
```

### Multi-Step Analysis Workflow

```ruby
agent "market-analyzer" do
  description "Analyze market trends and generate insights"

  mode :scheduled
  schedule "0 16 * * 1-5"  # 4 PM on weekdays

  workflow do
    # Gather data
    step :fetch_stock_prices do
      tool 'financial_api'
      params(
        action: 'get_prices',
        symbols: ['AAPL', 'GOOGL', 'MSFT', 'AMZN'],
        period: '1d'
      )
    end

    step :fetch_news do
      tool 'news_api'
      params(
        query: 'tech stocks',
        from: 'today'
      )
    end

    step :fetch_sentiment do
      tool 'twitter_api'
      params(
        topics: ['#tech', '#stocks'],
        limit: 100
      )
    end

    # Analysis
    step :analyze_price_trends do
      depends_on :fetch_stock_prices

      prompt <<~PROMPT
        Analyze these stock price movements and identify key trends:
        {fetch_stock_prices.output}

        Provide:
        1. Overall market direction
        2. Top performers
        3. Stocks showing unusual activity
      PROMPT
    end

    step :analyze_news_sentiment do
      depends_on :fetch_news

      prompt <<~PROMPT
        Analyze the sentiment of these news articles:
        {fetch_news.output}

        Categorize as: positive, negative, or neutral
        Identify key themes and concerns
      PROMPT
    end

    step :analyze_social_sentiment do
      depends_on :fetch_sentiment

      prompt <<~PROMPT
        Analyze social media sentiment:
        {fetch_sentiment.output}

        Summarize public perception of tech stocks
      PROMPT
    end

    # Synthesis
    step :generate_comprehensive_report do
      depends_on [:analyze_price_trends, :analyze_news_sentiment, :analyze_social_sentiment]

      prompt <<~PROMPT
        Create a comprehensive market analysis report combining:

        Price Analysis: {analyze_price_trends.output}
        News Sentiment: {analyze_news_sentiment.output}
        Social Sentiment: {analyze_social_sentiment.output}

        Generate an executive summary with:
        - Key market movements
        - Notable sentiment shifts
        - Potential opportunities or risks
        - Recommendation for tomorrow's trading strategy
      PROMPT
    end

    # Delivery
    step :send_report do
      depends_on :generate_comprehensive_report

      tool 'send_email'
      params(
        to: 'traders@company.com',
        subject: 'Daily Market Analysis - {today}',
        body: '{generate_comprehensive_report.output}',
        format: 'html'
      )
    end

    step :save_to_archive do
      depends_on :generate_comprehensive_report

      tool 'file_write'
      params(
        path: '/reports/market-analysis-{date}.md',
        content: '{generate_comprehensive_report.output}'
      )
    end
  end

  constraints do
    timeout '20m'
    max_iterations 30
    daily_budget 2000  # $20
  end
end
```

### Conditional Workflow

```ruby
agent "smart-responder" do
  description "Respond to customer inquiries with appropriate escalation"

  mode :reactive

  workflow do
    step :classify_inquiry do
      prompt <<~PROMPT
        Classify this customer inquiry:
        {event.inquiry_text}

        Categories:
        - simple: Can be answered with FAQ
        - technical: Requires technical expertise
        - billing: Related to billing/payments
        - urgent: Critical issue requiring immediate attention

        Respond with just the category name.
      PROMPT
    end

    step :check_if_urgent do
      depends_on :classify_inquiry

      execute do |context|
        category = context[:classify_inquiry][:output].strip.downcase
        { is_urgent: category == 'urgent' }
      end
    end

    step :send_urgent_alert do
      depends_on :check_if_urgent

      condition do |context|
        context[:check_if_urgent][:is_urgent]
      end

      tool 'send_sms'
      params(
        to: '+1-555-ONCALL',
        message: 'URGENT: Customer inquiry requires immediate attention - {event.ticket_id}'
      )
    end

    step :generate_response do
      depends_on :classify_inquiry

      prompt <<~PROMPT
        Generate an appropriate response for this {classify_inquiry.output} inquiry:
        {event.inquiry_text}

        Be helpful, professional, and concise.
      PROMPT
    end

    step :send_response do
      depends_on :generate_response

      tool 'email_send'
      params(
        to: '{event.customer_email}',
        subject: 'Re: {event.subject}',
        body: '{generate_response.output}'
      )
    end

    step :update_ticket do
      depends_on [:send_response, :check_if_urgent]

      tool 'crm_update'
      params(
        ticket_id: '{event.ticket_id}',
        status: 'responded',
        priority: '{check_if_urgent.is_urgent ? "high" : "normal"}',
        response: '{generate_response.output}'
      )
    end
  end
end
```

## Best Practices

### Workflow Design

1. **Keep steps focused** - Each step should do one thing well
2. **Name steps clearly** - Use descriptive names (`:fetch_user_data` not `:step1`)
3. **Handle errors explicitly** - Don't assume steps will succeed
4. **Use parallel execution** - Steps without dependencies run in parallel
5. **Minimize step count** - Combine related operations when sensible

### Error Handling

1. **Always handle critical failures** - Don't let workflows silently fail
2. **Provide fallback values** - Return sensible defaults on error
3. **Log failures** - Capture error details for debugging
4. **Use retries judiciously** - Retry transient failures, not logic errors
5. **Set appropriate timeouts** - Prevent indefinite hangs

### Performance

1. **Parallelize when possible** - Avoid unnecessary sequential dependencies
2. **Cache expensive operations** - Reuse results within workflow execution
3. **Set realistic timeouts** - Balance responsiveness with completion
4. **Monitor execution time** - Track and optimize slow steps

### Maintainability

1. **Document complex workflows** - Add comments explaining business logic
2. **Use consistent naming** - Follow conventions across all agents
3. **Test workflows** - Validate with dry-run mode before production
4. **Version control** - Track changes to workflow definitions

## See Also

- [Agent Reference](agent-reference.md) - Complete agent DSL reference
- [Constraints](constraints.md) - Resource and behavior limits
- [MCP Integration](mcp-integration.md) - External tool integration
- [Best Practices](best-practices.md) - Production deployment patterns
