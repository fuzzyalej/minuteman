require_relative "../test_helper"

describe Minuteman do
  before do
    @analytics = Minuteman.new

    today = Time.now.utc
    last_month  = today - (3600 * 24 * 30)
    last_week   = today - (3600 * 24 * 7)
    last_minute = today - 120

    @analytics.track("login", 12)
    @analytics.track("login", [2, 42])
    @analytics.track("login", 2, last_week)
    @analytics.track("login:successful", 567, last_month)

    @year_events   = @analytics.year("login", today)
    @week_events   = @analytics.week("login", today)
    @month_events  = @analytics.month("login", today)
    @day_events    = @analytics.day("login", today)
    @hour_events   = @analytics.hour("login", today)
    @minute_events = @analytics.minute("login", today)

    @last_week_events = @analytics.week("login", last_week)
    @last_minute_events = @analytics.minute("login", last_minute)
    @last_month_events = @analytics.month("login:successful", last_month)
  end

  after { @analytics.reset_all }

  it "should initialize correctly" do
    assert @analytics.redis
  end

  it "should track an event on a time" do
    assert_equal 3, @year_events.length
    assert_equal 3, @week_events.length
    assert_equal 1, @last_week_events.length
    assert_equal 1, @last_month_events.length
    assert_equal [true, true, false], @week_events.include?(12, 2, 1)

    assert @year_events.include?(12)
    assert @month_events.include?(12)
    assert @day_events.include?(12)
    assert @hour_events.include?(12)
    assert @minute_events.include?(12)

    assert @last_week_events.include?(2)
    assert !@month_events.include?(5)
    assert !@last_minute_events.include?(12)
    assert @last_month_events.include?(567)
  end

  it "should list all the events" do
    assert_equal 2, @analytics.events.size
    assert_equal ["login", "login:successful"], @analytics.events.sort
  end

  it "should reset all the keys" do
    assert_equal 2, @analytics.events.size

    @analytics.reset_all

    assert_equal 0, @analytics.events.size
  end

  it "should reset all bit operation keys" do
    @week_events & @last_week_events
    assert_equal 1, @analytics.operations.size

    @analytics.reset_operations_cache

    assert_equal 0, @analytics.operations.size
  end

  it "should accept the AND bitwise operations" do
    and_operation = @week_events & @last_week_events

    assert @week_events.include?(2)
    assert @week_events.include?(12)

    assert @last_week_events.include?(2)
    assert !@last_week_events.include?(12)

    assert_equal 1, and_operation.length

    assert !and_operation.include?(12)
    assert and_operation.include?(2)
  end

  it "should accept the OR bitwise operations" do
    or_operation = @week_events | @last_week_events

    assert @week_events.include?(2)
    assert @last_week_events.include?(2)
    assert !@last_week_events.include?(12)

    assert_equal 3, or_operation.length

    assert or_operation.include?(12)
    assert or_operation.include?(2)
  end

  it "should accept the NOT bitwise operations" do
    not_operation = ~@week_events

    assert @week_events.include?(2)
    assert @week_events.include?(12)

    assert !not_operation.include?(12)
    assert !not_operation.include?(2)
  end

  it "should have an alias for the OR operator" do
    or_operation = @week_events + @last_week_events

    assert @week_events.include?(2)
    assert @last_week_events.include?(2)
    assert !@last_week_events.include?(12)

    assert_equal 3, or_operation.length

    assert or_operation.include?(12)
    assert or_operation.include?(2)
  end

  it "should accept the substraction of a set" do
    substract_operation = @year_events - @week_events

    assert @week_events.include?(2)
    assert @year_events.include?(2)
    assert !substract_operation.include?(2)
  end

  it "should accept multiple consecutive operations" do
    multi_operation = @week_events & @last_week_events | @year_events

    assert_kind_of Minuteman::BitOperations::Result, multi_operation
  end

  it "should return the ids that belong to a given set" do
    ids = @week_events & [2, 12, 43]

    assert_kind_of Minuteman::BitOperations::Data, ids
    assert_equal [2, 12], ids
  end

  it "should return the ids that do not belong to the given set" do
    ids = @week_events - [2, 12, 43]

    assert_kind_of Minuteman::BitOperations::Data, ids
    assert_equal [43], ids
  end

  it "should return a set with data that behaves like an array" do
    ids = @week_events & [2, 12, 43]

    assert_kind_of Enumerator, ids.each
    assert_kind_of Enumerator, ids.map
    assert_equal 2, ids.size
  end
end

describe "Using options" do
  it "should be able to stop using the cache" do
    minuteman = Minuteman.new
    assert_equal true, minuteman.options[:cache]

    minuteman.options[:cache] = false

    assert_equal false, minuteman.options[:cache]
  end
end

describe "Changing the Minuteman time spans" do
  it "should be able to change the span and ignore minute" do
    time_spans = %w[year month day hour]
    minuteman = Minuteman.new(time_spans: time_spans)

    minuteman.track("login", 12)

    assert_equal 4, minuteman.redis.keys.size
    assert_equal time_spans, minuteman.options[:time_spans]

    assert minuteman.respond_to?(:year)
    assert minuteman.respond_to?(:month)
    assert minuteman.respond_to?(:day)
    assert minuteman.respond_to?(:hour)

    assert !minuteman.respond_to?(:minute)
    assert !minuteman.respond_to?(:week)
  end
end

describe "Changing Minuteman redis connections" do
  it "should support using a Redis instance" do
    redis = Redis.new
    minuteman = Minuteman.new(redis: redis)

    assert_equal redis, Minuteman.redis
    assert_equal redis, minuteman.redis
  end

  it "should support changing the current connection" do
    redis = Redis.new
    minuteman = Minuteman.new

    assert redis != Minuteman.redis

    minuteman.redis = redis

    assert_equal redis, minuteman.redis
  end

  it "should support Redis::Namespace" do
    namespace = Redis::Namespace.new(:ns, redis: Redis.new)

    minuteman = Minuteman.new(redis: namespace)

    assert_equal namespace, Minuteman.redis
    assert_equal namespace, minuteman.redis
  end

  it "should fail silently" do
    minuteman = Minuteman.new(silent: true, redis: { port: 1234 })

    minuteman.track("test", 1)
  end

  it "should fail loudly" do
    minuteman = Minuteman.new(redis: { port: 1234 })

    assert_raises Redis::CannotConnectError do
      minuteman.track("test", 1)
    end
  end
end
