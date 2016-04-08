class TwimlResponders::KnockKnockJoke
  attr_reader :params

  def initialize(params, session)
    @params = params

    session[:knock_knock_joke] ||= {}
    session[:knock_knock_joke][:step] ||= 0
    @session = session
  end

  def call
    Twilio::TwiML::Response.new do |r|
      case step
      when 0
        r.Message "Who's there?"
        increment_step
      when 1
        r.Message "#{params[:Body]} who?"
        increment_step
      when 2
        r.Message punch_line_response
        cleanup_session
      end
    end
  end

  private

  def step
    @session[:knock_knock_joke][:step]
  end

  def increment_step
    @session[:knock_knock_joke][:step] += 1
  end

  def cleanup_session
    @session.delete :knock_knock_joke
  end

  def punch_line_response
    ['Good one', 'That was corny', 'Lol', 'Haha'].sample
  end
end
