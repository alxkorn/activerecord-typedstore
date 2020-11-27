# frozen_string_literal: true

require 'active_record/typed_store/dsl'
require 'active_record/typed_store/behavior'
require 'active_record/typed_store/type'
require 'active_record/typed_store/typed_hash'
require 'active_record/typed_store/identity_coder'

module ActiveRecord::TypedStore
  module Extension
    def store_accessor(store_attribute, *keys, prefix: nil, suffix: nil)
      if ActiveRecord.version < Gem::Version.new('6.0.0')
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
      else
        super(store_attribute, *keys, prefix, suffix)
      end
    end

    def typed_store(store_attribute, options={}, &block)
      unless self < Behavior
        include Behavior
        class_attribute :typed_stores, :store_accessors, instance_accessor: false
      end

      dsl = DSL.new(store_attribute, options, &block)
      self.typed_stores = (self.typed_stores || {}).merge(store_attribute => dsl)
      self.store_accessors = typed_stores.each_value.flat_map(&:accessors).map { |a| -a.to_s }.to_set

      typed_klass = TypedHash.create(dsl.fields.values)
      const_set("#{store_attribute}_hash".camelize, typed_klass)

      if ActiveRecord.version >= Gem::Version.new('6.1.0.alpha')
        attribute(store_attribute) do |subtype|
          Type.new(typed_klass, dsl.coder, subtype)
        end
      else
        decorate_attribute_type(store_attribute, :typed_store) do |subtype|
          Type.new(typed_klass, dsl.coder, subtype)
        end
      end

      if ActiveRecord.version >= Gem::Version.new('6.0.0')
        store_accessor(store_attribute, dsl.accessors, prefix: options[:prefix], suffix: options[:suffix])
      else
        store_accessor(store_attribute, dsl.accessors)
      end
    end
  end
end
