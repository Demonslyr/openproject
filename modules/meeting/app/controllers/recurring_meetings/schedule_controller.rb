module RecurringMeetings
  class ScheduleController < ApplicationController
    before_action do
      do_authorize :create_meetings, global: true
    end
    authorization_checked! :update_text

    around_action :with_user_time_zone
    before_action :build_meeting

    def update_text
      text = @recurring_meeting.human_frequency_schedule
      respond_to do |format|
        format.html { render plain: text }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("recurring-meeting-frequency-schedule",
                                                   plain: text)
        end
      end
    end

    private

    def with_user_time_zone(&)
      User.execute_as(User.current, &)
    end

    def build_meeting
      @recurring_meeting = RecurringMeeting.new(schedule_params.compact_blank)
    end

    def schedule_params
      params
        .require(:meeting)
        .permit(:start_date, :start_time_hour, :frequency, :interval)
    end

    def default_breadcrumb; end
  end
end
