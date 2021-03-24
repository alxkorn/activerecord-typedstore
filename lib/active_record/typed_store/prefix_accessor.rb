# frozen_string_literal: true

module ActiveRecord::TypedStore
  module PrefixAccessor
    def prefix_store_accessor(store_attribute, *keys, prefix: nil, suffix: nil)
      keys = keys.flatten

      accessor_prefix =
        case prefix
        when String, Symbol
          "#{prefix}_"
        when TrueClass
          "#{store_attribute}_"
        else
          ""
        end
      accessor_suffix =
        case suffix
        when String, Symbol
          "_#{suffix}"
        when TrueClass
          "_#{store_attribute}"
        else
          ""
        end

      _store_accessors_module.module_eval do
        keys.each do |key|
          accessor_key = "#{accessor_prefix}#{key}#{accessor_suffix}"

          define_method("#{accessor_key}=") do |value|
            write_store_attribute(store_attribute, key, value)
          end

          define_method(accessor_key) do
            read_store_attribute(store_attribute, key)
          end

          define_method("#{accessor_key}_changed?") do
            return false unless attribute_changed?(store_attribute)
            prev_store, new_store = changes[store_attribute]
            prev_store&.dig(key) != new_store&.dig(key)
          end

          define_method("#{accessor_key}_change") do
            return unless attribute_changed?(store_attribute)
            prev_store, new_store = changes[store_attribute]
            [prev_store&.dig(key), new_store&.dig(key)]
          end

          define_method("#{accessor_key}_was") do
            return unless attribute_changed?(store_attribute)
            prev_store, _new_store = changes[store_attribute]
            prev_store&.dig(key)
          end

          define_method("saved_change_to_#{accessor_key}?") do
            return false unless saved_change_to_attribute?(store_attribute)
            prev_store, new_store = saved_change_to_attribute(store_attribute)
            prev_store&.dig(key) != new_store&.dig(key)
          end

          define_method("saved_change_to_#{accessor_key}") do
            return unless saved_change_to_attribute?(store_attribute)
            prev_store, new_store = saved_change_to_attribute(store_attribute)
            [prev_store&.dig(key), new_store&.dig(key)]
          end

          define_method("#{accessor_key}_before_last_save") do
            return unless saved_change_to_attribute?(store_attribute)
            prev_store, _new_store = saved_change_to_attribute(store_attribute)
            prev_store&.dig(key)
          end
        end
      end

      # assign new store attribute and create new hash to ensure that each class in the hierarchy
      # has its own hash of stored attributes.
      self.local_stored_attributes ||= {}
      self.local_stored_attributes[store_attribute] ||= []
      self.local_stored_attributes[store_attribute] |= keys
    end
  end
end
