# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class Trigger < ApplicationModel
  include ChecksConditionValidation
  include CanSeed

  load 'trigger/assets.rb'
  include Trigger::Assets

  store     :condition
  store     :perform
  validates :name, presence: true
end
