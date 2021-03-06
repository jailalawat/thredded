require 'thredded/search_sql_builder'

module Thredded
  class Topic < ActiveRecord::Base
    extend FriendlyId
    friendly_id :title, use: [:history, :scoped], scope: :messageboard

    paginates_per 50 if self.respond_to?(:paginates_per)

    has_many :posts,
      -> { includes :attachments },
      as: :postable,
      dependent: :destroy
    has_many :topic_categories, dependent: :destroy
    has_many :categories, through: :topic_categories
    has_many :user_topic_reads, dependent: :destroy
    has_one :user_detail, through: :user, source: :thredded_user_detail

    belongs_to :user, class_name: Thredded.user_class
    belongs_to \
      :last_user,
      class_name: Thredded.user_class,
      foreign_key: 'last_user_id'
    belongs_to \
      :messageboard,
      counter_cache: true,
      touch: true

    validates_presence_of :hash_id
    validates_presence_of :last_user_id
    validates_presence_of :messageboard_id
    validates_numericality_of :posts_count
    validates_uniqueness_of :hash_id

    delegate :name, :name=, :email, :email=, to: :user, prefix: true

    before_validation do
      self.hash_id = SecureRandom.hex(10) if hash_id.nil?
    end

    after_create :increment_topics_count

    def self.stuck
      where(sticky: true)
    end

    def self.unstuck
      where(sticky: false)
    end

    def self.on_page(page_num)
      page(page_num).per(30)
    end

    def self.for_messageboard(messageboard)
      where(messageboard_id: messageboard.id)
    end

    def self.order_by_updated_time
      order('thredded_topics.updated_at DESC')
    end

    def self.order_by_stuck_and_updated_time
      order('thredded_topics.sticky DESC, thredded_topics.updated_at DESC')
    end

    def self.search(query, messageboard)
      sql_builder = SearchSqlBuilder.new(query, messageboard)
      sql = sql_builder.build
      sql_params = [sql].concat(sql_builder.binds)
      results = find_by_sql(sql_params)

      fail(Thredded::Errors::EmptySearchResults, query) if results.empty?

      results
    end

    def self.decorate
      all.map do |topic|
        TopicDecorator.new(topic)
      end
    end

    def self.find_by_slug_with_user_topic_reads!(slug)
      includes(:user_topic_reads).friendly.find(slug)
    rescue ActiveRecord::RecordNotFound
      raise Thredded::Errors::TopicNotFound
    end

    def decorate
      TopicDecorator.new(self)
    end

    def user
      super || NullUser.new
    end

    def last_user
      super || NullUser.new
    end

    def public?
      true
    end

    def private?
      false
    end

    def self.inherited(child)
      child.instance_eval do
        def model_name
          Topic.model_name
        end
      end

      super
    end

    def self.select_options
      subclasses.map(&:to_s).sort
    end

    def self.recent
      limit(10)
    end

    def updating?
      id.present?
    end

    def categories_to_sentence
      categories.map(&:name).to_sentence if categories.any?
    end

    def users_to_sentence
      []
    end

    def should_generate_new_friendly_id?
      title_changed?
    end

    private

    def increment_topics_count
      user_detail.increment!(:topics_count) if user_detail
    end
  end
end
