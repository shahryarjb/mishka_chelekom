defmodule DevelopmentWeb.Components.Headless.ChatApproval do
  @moduledoc """
  Headless **chat_approval** — the agent stops and asks the human (human-in-the-loop).

  Two shapes, one component:

    * **approve / deny** — no `:option` slots: "Delete 3 files?" with an approve button (submits
      the form) and a deny button (sends `on_deny`)
    * **a question** — `:option` slots render native radio buttons (or checkboxes with
      `multiple`) inside a fieldset whose legend is the `title`, plus an optional free-text
      "something else" answer (`allow_custom`)

  Everything is a plain form: `on_submit` receives `%{"approval" => value}` (the key is `name`;
  a list with `multiple`) and `"approval_custom"` for the free text. Native controls give the
  keyboard behaviour for free (arrow keys move between radios).

  Once decided, set `status` to `approved`, `denied` or `answered`: the fieldset is disabled, so
  the choice stays visible but cannot be changed.

      <.chat_approval id="q-1" title="Which market do we enter first?" on_submit="answer">
        <:option value="trucks" label="Food trucks" />
        <:option value="grocery" label="Grocery freezers" description="Needs a distributor" />
      </.chat_approval>

  Parts: `fieldset`, `title`, `description`, `options`, `option`, `option-input`, `option-label`,
  `option-description`, `custom`, `actions`, `approve`, `deny`.

  Ships **no** colors, sizing or spacing — style via `chelekom-chat-approval*`.

  **Documentation:** https://mishka.tools/chelekom/docs/headless/chat_approval
  """
  use Phoenix.Component

  @doc type: :component
  attr :id, :string, required: true, doc: "Unique id of the form"
  attr :title, :string, required: true, doc: "The question (the fieldset legend)"
  attr :description, :string, default: nil, doc: "Context under the title"
  attr :name, :string, default: "approval", doc: "Field name of the chosen option(s)"
  attr :multiple, :boolean, default: false, doc: "Checkboxes instead of radio buttons"

  attr :status, :string,
    default: "pending",
    values: ~w(pending approved denied answered),
    doc: "Once decided, the fieldset is disabled"

  attr :on_submit, :string, default: nil, doc: "LiveView event for the form (approve / answer)"
  attr :on_deny, :string, default: nil, doc: "LiveView event for the deny button"
  attr :target, :any, default: nil, doc: "phx-target for the form and the deny button"
  attr :allow_custom, :boolean, default: false, doc: "Offer a free-text answer"
  attr :custom_placeholder, :string, default: "Something else…", doc: "Placeholder of it"

  attr :approve_label, :string,
    default: nil,
    doc: ~s|Approve text (default "Approve", "Continue" with options)|

  attr :deny_label, :string,
    default: nil,
    doc: ~s|Deny text (default "Deny", "Skip" with options)|

  attr :class, :any, default: nil, doc: "Extra classes for the root"
  attr :fieldset_class, :any, default: nil, doc: ~s|Extra classes for `data-part="fieldset"`|
  attr :title_class, :any, default: nil, doc: ~s|Extra classes for `data-part="title"`|

  attr :description_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="description"`|

  attr :options_class, :any, default: nil, doc: ~s|Extra classes for `data-part="options"`|
  attr :option_class, :any, default: nil, doc: ~s|Extra classes for every `data-part="option"`|

  attr :option_input_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="option-input"`|

  attr :option_label_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="option-label"`|

  attr :option_description_class, :any,
    default: nil,
    doc: ~s|Extra classes for `data-part="option-description"`|

  attr :custom_class, :any, default: nil, doc: ~s|Extra classes for `data-part="custom"`|
  attr :actions_class, :any, default: nil, doc: ~s|Extra classes for `data-part="actions"`|
  attr :approve_class, :any, default: nil, doc: ~s|Extra classes for `data-part="approve"`|
  attr :deny_class, :any, default: nil, doc: ~s|Extra classes for `data-part="deny"`|
  attr :rest, :global

  slot :option, doc: "One choice" do
    attr :value, :string, required: true
    attr :label, :string, required: true
    attr :description, :string
    attr :checked, :boolean
  end

  slot :inner_block, doc: "Extra context (a diff, the command about to run)"

  def chat_approval(assigns) do
    has_options = assigns.option != []

    assigns =
      assigns
      |> assign(:has_options, has_options)
      |> assign(:type, if(assigns.multiple, do: "checkbox", else: "radio"))
      |> assign(:field, if(assigns.multiple, do: assigns.name <> "[]", else: assigns.name))
      |> assign(:decided, assigns.status != "pending")
      |> assign(
        :approve_text,
        assigns.approve_label || if(has_options, do: "Continue", else: "Approve")
      )
      |> assign(:deny_text, assigns.deny_label || if(has_options, do: "Skip", else: "Deny"))

    ~H"""
    <form
      id={@id}
      phx-submit={@on_submit}
      phx-target={@target}
      data-part="root"
      data-status={@status}
      class={["chelekom-chat-approval", @class]}
      {@rest}
    >
      <fieldset
        disabled={@decided}
        aria-describedby={@description && "#{@id}-description"}
        data-part="fieldset"
        class={["chelekom-chat-approval__fieldset", @fieldset_class]}
      >
        <legend data-part="title" class={["chelekom-chat-approval__title", @title_class]}>
          {@title}
        </legend>
        <p
          :if={@description}
          id={"#{@id}-description"}
          data-part="description"
          class={["chelekom-chat-approval__description", @description_class]}
        >
          {@description}
        </p>

        {render_slot(@inner_block)}

        <div
          :if={@has_options}
          data-part="options"
          class={["chelekom-chat-approval__options", @options_class]}
        >
          <label
            :for={{option, index} <- Enum.with_index(@option)}
            data-part="option"
            class={["chelekom-chat-approval__option", @option_class]}
          >
            <input
              type={@type}
              id={"#{@id}-option-#{index}"}
              name={@field}
              value={option.value}
              checked={option[:checked]}
              data-part="option-input"
              class={["chelekom-chat-approval__option-input", @option_input_class]}
            />
            <span
              data-part="option-label"
              class={["chelekom-chat-approval__option-label", @option_label_class]}
            >
              {option.label}
            </span>
            <span
              :if={option[:description]}
              data-part="option-description"
              class={["chelekom-chat-approval__option-description", @option_description_class]}
            >
              {option.description}
            </span>
          </label>
        </div>

        <input
          :if={@allow_custom}
          type="text"
          name={@name <> "_custom"}
          placeholder={@custom_placeholder}
          aria-label={@custom_placeholder}
          data-part="custom"
          class={["chelekom-chat-approval__custom", @custom_class]}
        />

        <div data-part="actions" class={["chelekom-chat-approval__actions", @actions_class]}>
          <button
            :if={@on_deny}
            type="button"
            phx-click={@on_deny}
            phx-target={@target}
            data-part="deny"
            class={["chelekom-chat-approval__deny", @deny_class]}
          >
            {@deny_text}
          </button>
          <button
            type="submit"
            data-part="approve"
            class={["chelekom-chat-approval__approve", @approve_class]}
          >
            {@approve_text}
          </button>
        </div>
      </fieldset>
    </form>
    """
  end
end
