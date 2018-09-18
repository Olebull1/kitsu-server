class StatWorker
  include Sidekiq::Worker

  # @param stat [String] the class name of the stat to act upon
  # @param user_id [Integer] the ID of the user whose stat we are modifying
  # @param action ['update','create','destroy'] the action to perform
  # @param model [Hash] the model data to rehydrate on the worker
  #   @option model [String] 'class' the class name of the model to rehydrate into
  #   @option model [Hash] 'attributes' the attributes to rehydrate into the model
  # @param changes [Hash<String,Array<Object>>] a list of change state to apply on top of the model
  def perform(stat, user_id, action, model, changes)
    # Bail if the User has stopped existing (deletion)
    return unless User.exists?(user_id)
    # Load the stat
    stat = stat.constantize.for_user(user_id)
    return unless stat.respond_to?("on_#{action}")
    # Rehydrate the model
    model_class, model_attributes = model.values_at('class', 'attributes')
    model = model_class.constantize.new(model_attributes)
    # Wrap the model in a DirtyChangeWrapper to make it appear dirty
    wrapper = DirtyChangeWrapper.new(model, changes)
    # Lock the User's stat row so no other workers can update it
    stat.with_lock do
      # Call down to the stat to run the action
      stat.public_send("on_#{action}", wrapper)
    end
  end

  # @see #perform
  def self.perform_async(stat, user, action, model)
    attributes = model.attributes
    changes = model.changes
    super(stat, user.id, action, { class: model.class.name, attributes: attributes }, changes)
  end
end
