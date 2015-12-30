# This fix is based on:
#   * https://github.com/clemens/delocalize/issues/74
#   * https://gist.github.com/daniel-rikowski/fd09dc2cc82ce28e7986

require 'active_record'

# let's hack into ActiveRecord a bit - everything at the lowest possible level, of course, so we minimalize side effects
ActiveRecord::ConnectionAdapters::Column.class_eval do
  def date?
    klass == Date
  end

  def time?
    klass == Time
  end
end

module ActiveRecord::AttributeMethods::Write
  def type_cast_attribute_for_write(column, value)
    return value unless column

    value = Numeric.parse_localized(value) if column.number? && I18n.delocalization_enabled?
    column.type_cast_for_write value
  end
end

ActiveRecord::Base.class_eval do
  def write_attribute_with_localization(attr_name, original_value)
    new_value = original_value
    if column = column_for_attribute(attr_name.to_s)
      if column.date?
        new_value = Date.parse_localized(original_value) rescue original_value
      elsif column.time?
        new_value = Time.parse_localized(original_value) rescue original_value
      end
    end
    write_attribute_without_localization(attr_name, new_value)
  end
  alias_method_chain :write_attribute, :localization

  protected
  
  def self.define_method_attribute=(attr_name)
    if create_time_zone_conversion_attribute?(attr_name, columns_hash[attr_name])
      method_body, line = <<-EOV, __LINE__ + 1
        def #{attr_name}=(original_time)
          time = original_time
          unless time.acts_like?(:time)
            time = time.is_a?(String) ? (I18n.delocalization_enabled? ? Time.zone.parse_localized(time) : Time.zone.parse(time)) : time.to_time rescue time
          end
          time = time.in_time_zone rescue nil if time
          write_attribute(:#{attr_name}, original_time)
        end
      EOV
      generated_attribute_methods.module_eval(method_body, __FILE__, line)
    else
      super
    end
  end
end

module ActiveRecord
  module Type
    class Decimal
      def type_cast_from_user(value)
        value = ::Numeric.parse_localized(value)
        type_cast(value)
      end
    end

    class Time
      def type_cast_from_user(value)
        value = ::Time.parse_localized(value) rescue value
        type_cast(value)
      end
    end

    class DateTime
      def type_cast_from_user(value)
        value = ::DateTime.parse_localized(value) rescue value
        type_cast(value)
      end
    end

    class Date
      def type_cast_from_user(value)
        value = ::Date.parse_localized(value) rescue value
        type_cast(value)
      end
    end

    module Numeric
      def non_numeric_string?(value)
        # TODO: Cache!
        value.to_s !~ /\A\d+#{Regexp.escape(I18n.t(:'number.format.separator'))}?\d*\z/
      end
    end
  end
end
