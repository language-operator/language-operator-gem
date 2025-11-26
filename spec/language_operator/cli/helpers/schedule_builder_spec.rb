# frozen_string_literal: true

require 'spec_helper'
require 'language_operator/cli/helpers/schedule_builder'

RSpec.describe LanguageOperator::CLI::Helpers::ScheduleBuilder do
  describe '.parse_time' do
    context 'with 24-hour format' do
      it 'parses valid 24-hour times' do
        expect(described_class.parse_time('16:00')).to eq('16:00')
        expect(described_class.parse_time('9:30')).to eq('09:30')
        expect(described_class.parse_time('00:00')).to eq('00:00')
        expect(described_class.parse_time('23:59')).to eq('23:59')
      end

      it 'raises error for invalid 24-hour times' do
        expect { described_class.parse_time('24:00') }.to raise_error(ArgumentError, 'Invalid time: 24:00')
        expect { described_class.parse_time('12:60') }.to raise_error(ArgumentError, 'Invalid time: 12:60')
      end
    end

    context 'with 12-hour format' do
      it 'parses valid 12-hour times with am' do
        expect(described_class.parse_time('9am')).to eq('09:00')
        expect(described_class.parse_time('12am')).to eq('00:00')
        expect(described_class.parse_time('0am')).to eq('00:00')
        expect(described_class.parse_time('9:30am')).to eq('09:30')
      end

      it 'parses valid 12-hour times with pm' do
        expect(described_class.parse_time('4pm')).to eq('16:00')
        expect(described_class.parse_time('12pm')).to eq('12:00')
        expect(described_class.parse_time('4:30pm')).to eq('16:30')
      end

      it 'raises error for invalid 12-hour times' do
        expect { described_class.parse_time('13pm') }.to raise_error(ArgumentError, 'Invalid time: 13pm')
        expect { described_class.parse_time('25am') }.to raise_error(ArgumentError, 'Invalid time: 25am')
      end
    end

    it 'raises error for invalid format' do
      expect { described_class.parse_time('invalid') }.to raise_error(ArgumentError, 'Invalid time format: invalid')
      expect { described_class.parse_time('25:00') }.to raise_error(ArgumentError, 'Invalid time: 25:00')
    end
  end

  describe '.daily_cron' do
    it 'builds correct daily cron expressions' do
      expect(described_class.daily_cron('16:00')).to eq('0 16 * * *')
      expect(described_class.daily_cron('09:30')).to eq('30 9 * * *')
      expect(described_class.daily_cron('00:00')).to eq('0 0 * * *')
    end
  end

  describe '.interval_cron' do
    context 'with valid intervals' do
      it 'builds correct minute intervals' do
        expect(described_class.interval_cron(1, 'minutes')).to eq('*/1 * * * *')
        expect(described_class.interval_cron(30, 'minute')).to eq('*/30 * * * *')
        expect(described_class.interval_cron(59, 'minutes')).to eq('*/59 * * * *')
      end

      it 'builds correct hour intervals' do
        expect(described_class.interval_cron(1, 'hours')).to eq('0 */1 * * *')
        expect(described_class.interval_cron(6, 'hour')).to eq('0 */6 * * *')
        expect(described_class.interval_cron(23, 'hours')).to eq('0 */23 * * *')
      end

      it 'builds correct day intervals' do
        expect(described_class.interval_cron(1, 'days')).to eq('0 0 */1 * *')
        expect(described_class.interval_cron(7, 'day')).to eq('0 0 */7 * *')
        expect(described_class.interval_cron(31, 'days')).to eq('0 0 */31 * *')
      end
    end

    context 'with invalid intervals' do
      it 'rejects intervals that are not positive integers' do
        expect { described_class.interval_cron(0, 'minutes') }.to raise_error(
          ArgumentError, 'Interval must be a positive integer, got: 0'
        )
        expect { described_class.interval_cron(-1, 'hours') }.to raise_error(
          ArgumentError, 'Interval must be a positive integer, got: -1'
        )
        expect { described_class.interval_cron('5', 'days') }.to raise_error(
          ArgumentError, 'Interval must be a positive integer, got: 5'
        )
      end

      it 'rejects minute intervals >= 60' do
        expect { described_class.interval_cron(60, 'minutes') }.to raise_error(
          ArgumentError, 'Minutes interval must be between 1-59, got: 60'
        )
        expect { described_class.interval_cron(120, 'minute') }.to raise_error(
          ArgumentError, 'Minutes interval must be between 1-59, got: 120'
        )
      end

      it 'rejects hour intervals >= 24' do
        expect { described_class.interval_cron(24, 'hours') }.to raise_error(
          ArgumentError, 'Hours interval must be between 1-23, got: 24'
        )
        expect { described_class.interval_cron(48, 'hour') }.to raise_error(
          ArgumentError, 'Hours interval must be between 1-23, got: 48'
        )
      end

      it 'rejects day intervals >= 32' do
        expect { described_class.interval_cron(32, 'days') }.to raise_error(
          ArgumentError, 'Days interval must be between 1-31, got: 32'
        )
        expect { described_class.interval_cron(365, 'day') }.to raise_error(
          ArgumentError, 'Days interval must be between 1-31, got: 365'
        )
      end

      it 'rejects invalid units' do
        expect { described_class.interval_cron(5, 'seconds') }.to raise_error(
          ArgumentError, 'Invalid unit: seconds'
        )
        expect { described_class.interval_cron(5, 'weeks') }.to raise_error(
          ArgumentError, 'Invalid unit: weeks'
        )
      end
    end
  end

  describe '.cron_to_human' do
    it 'converts daily cron expressions to human readable format' do
      expect(described_class.cron_to_human('0 16 * * *')).to eq('Daily at 16:00')
      expect(described_class.cron_to_human('30 9 * * *')).to eq('Daily at 09:30')
    end

    it 'converts minute interval cron expressions' do
      expect(described_class.cron_to_human('*/5 * * * *')).to eq('Every 5 minutes')
      expect(described_class.cron_to_human('*/1 * * * *')).to eq('Every 1 minute')
      expect(described_class.cron_to_human('*/30 * * * *')).to eq('Every 30 minutes')
    end

    it 'converts hour interval cron expressions' do
      expect(described_class.cron_to_human('0 */6 * * *')).to eq('Every 6 hours')
      expect(described_class.cron_to_human('0 */1 * * *')).to eq('Every 1 hour')
      expect(described_class.cron_to_human('0 */12 * * *')).to eq('Every 12 hours')
    end

    it 'converts day interval cron expressions' do
      expect(described_class.cron_to_human('0 0 */7 * *')).to eq('Every 7 days')
      expect(described_class.cron_to_human('0 0 */1 * *')).to eq('Every 1 day')
      expect(described_class.cron_to_human('0 0 */14 * *')).to eq('Every 14 days')
    end

    it 'returns original expression for unsupported formats' do
      expect(described_class.cron_to_human('0 0 1 * *')).to eq('0 0 1 * *')
      expect(described_class.cron_to_human('invalid')).to eq('invalid')
    end
  end
end
