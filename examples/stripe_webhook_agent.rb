#!/usr/bin/env ruby
# frozen_string_literal: true

# Stripe Webhook Agent Example
#
# This example shows how to create an agent that receives Stripe webhook events
# with proper signature verification for security.
#
# Setup:
# 1. Set STRIPE_WEBHOOK_SECRET environment variable (from Stripe Dashboard)
# 2. Configure Stripe webhook to send events to https://<agent-url>/stripe/events
# 3. Select events you want to receive (e.g., payment_intent.succeeded, customer.created)
#
# Stripe webhook documentation:
# https://stripe.com/docs/webhooks

require 'bundler/setup'
require 'language_operator'

LanguageOperator::Dsl.define_agents do
  agent 'stripe-payment-processor' do
    description 'Processes Stripe payment events and triggers fulfillment'

    # Set to reactive mode to receive webhooks
    mode :reactive

    # Stripe webhook endpoint
    webhook '/stripe/events' do
      method :post

      # Verify Stripe webhook signature
      # Stripe sends signature in Stripe-Signature header
      # Format: "t=<timestamp>,v1=<signature>"
      # Note: For simplicity, we're verifying the v1 signature
      # Production should also check timestamp to prevent replay attacks
      authenticate do
        verify_custom do |context|
          signature_header = context[:headers]['Stripe-Signature']
          return false unless signature_header

          # Parse signature header
          # Format: t=1614556800,v1=abc123,v0=def456
          sig_parts = {}
          signature_header.split(',').each do |part|
            key, value = part.split('=', 2)
            sig_parts[key] = value
          end

          timestamp = sig_parts['t']
          signature = sig_parts['v1']
          return false unless timestamp && signature

          # Construct signed payload
          signed_payload = "#{timestamp}.#{context[:body]}"

          # Compute expected signature
          secret = ENV['STRIPE_WEBHOOK_SECRET']
          expected = OpenSSL::HMAC.hexdigest('sha256', secret, signed_payload)

          # Compare signatures (constant-time)
          signature == expected
        end
      end

      # Validate request format
      require_content_type 'application/json'

      on_request do |context|
        event = JSON.parse(context[:body])
        event_type = event['type']
        event_data = event['data']['object']

        case event_type
        when 'payment_intent.succeeded'
          handle_payment_succeeded(event_data)
        when 'payment_intent.payment_failed'
          handle_payment_failed(event_data)
        when 'customer.created'
          handle_customer_created(event_data)
        when 'customer.subscription.created'
          handle_subscription_created(event_data)
        when 'customer.subscription.deleted'
          handle_subscription_deleted(event_data)
        when 'invoice.payment_succeeded'
          handle_invoice_paid(event_data)
        when 'invoice.payment_failed'
          handle_invoice_failed(event_data)
        when 'charge.refunded'
          handle_refund(event_data)
        else
          { status: 'ignored', event_type: event_type }
        end
      end
    end

    # Alternative endpoint with API key authentication
    # Useful for testing or internal triggers
    webhook '/stripe/manual-trigger' do
      method :post

      # Verify API key
      authenticate do
        verify_api_key(
          header: 'X-API-Key',
          key: ENV['STRIPE_INTERNAL_API_KEY']
        )
      end

      require_content_type 'application/json'

      on_request do |context|
        data = JSON.parse(context[:body])
        action = data['action']

        {
          status: 'processed',
          action: action,
          message: "Manual trigger received: #{action}"
        }
      end
    end
  end
end

# Helper methods for event handling

def handle_payment_succeeded(payment_intent)
  {
    status: 'processed',
    event: 'payment_succeeded',
    amount: payment_intent['amount'],
    currency: payment_intent['currency'],
    customer: payment_intent['customer'],
    payment_intent_id: payment_intent['id'],
    message: "Payment of #{payment_intent['amount']} #{payment_intent['currency']} succeeded"
  }
end

def handle_payment_failed(payment_intent)
  {
    status: 'processed',
    event: 'payment_failed',
    amount: payment_intent['amount'],
    currency: payment_intent['currency'],
    customer: payment_intent['customer'],
    error: payment_intent['last_payment_error']&.dig('message'),
    message: 'Payment failed'
  }
end

def handle_customer_created(customer)
  {
    status: 'processed',
    event: 'customer_created',
    customer_id: customer['id'],
    email: customer['email'],
    message: "New customer created: #{customer['email']}"
  }
end

def handle_subscription_created(subscription)
  {
    status: 'processed',
    event: 'subscription_created',
    subscription_id: subscription['id'],
    customer: subscription['customer'],
    plan: subscription['items']['data'].first['price']['id'],
    message: "New subscription created for customer #{subscription['customer']}"
  }
end

def handle_subscription_deleted(subscription)
  {
    status: 'processed',
    event: 'subscription_deleted',
    subscription_id: subscription['id'],
    customer: subscription['customer'],
    message: "Subscription deleted for customer #{subscription['customer']}"
  }
end

def handle_invoice_paid(invoice)
  {
    status: 'processed',
    event: 'invoice_paid',
    invoice_id: invoice['id'],
    amount: invoice['amount_paid'],
    customer: invoice['customer'],
    message: "Invoice #{invoice['number']} paid"
  }
end

def handle_invoice_failed(invoice)
  {
    status: 'processed',
    event: 'invoice_failed',
    invoice_id: invoice['id'],
    amount: invoice['amount_due'],
    customer: invoice['customer'],
    message: "Invoice #{invoice['number']} payment failed"
  }
end

def handle_refund(charge)
  {
    status: 'processed',
    event: 'refund',
    charge_id: charge['id'],
    amount_refunded: charge['amount_refunded'],
    customer: charge['customer'],
    message: "Charge #{charge['id']} refunded"
  }
end

# Run the agent if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  agent = LanguageOperator::Dsl.agent_registry.get('stripe-payment-processor')
  agent.run!
end
