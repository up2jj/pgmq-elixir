defmodule Pgmq do
  @moduledoc """
  Thin wrapper over the pgmq extension

  This module can be `use`d for the convenience of having a standardized repo
  and encoder for all messages.

  Example usage:
  ```
    # lib/my_app/pgmq.ex
    defmodule MyApp.Pgmq do
      use Pgmq, repo: MyApp.Repo, encoder: Jason
    end
  ```

  would allow you to call `MyApp.Pgmq.send_message("myqueue", %{"hi" => "world!"})`

  Alternatively, one can call the functions from this module directly. For example,
  `Pgmq.send_message(MyApp.Repo, "myqueue", Jason.encode!(%{"hi" => "world!"}))`
  """

  alias Pgmq.Message

  @type queue :: String.t()
  @type repo :: Ecto.Repo.t()

  @default_max_poll_seconds 5
  @default_poll_interval_ms 250

  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    encoder = Keyword.fetch!(opts, :encoder)

    quote do
      @spec create_queue(Pgmq.queue()) :: :ok
      def create_queue(queue), do: Pgmq.create_queue(unquote(repo), queue)

      @spec drop_queue(Pgmq.queue()) :: :ok
      def drop_queue(queue), do: Pgmq.drop_queue(unquote(repo), queue)

      @spec send_message(Pgmq.queue(), term()) :: {:ok, integer()} | {:error, term()}
      def send_message(queue, message) do
        with {:ok, encoded_message} <- unquote(encoder).encode(message) do
          Pgmq.send_message(unquote(repo), queue, encoded_message)
        end
      end

      @spec read_message(Pgmq.queue(), integer()) :: Pgmq.Message.t() | nil
      def read_message(queue, visibility_timeout_seconds) do
        Pgmq.read_message(unquote(repo), queue, visibility_timeout_seconds)
      end

      @spec read_messages(
              Pgmq.queue(),
              visibility_timeout_seconds :: integer(),
              count :: integer()
            ) :: [Pgmq.Message.t()]
      def read_messages(queue, visibility_timeout_seconds, count) do
        Pgmq.read_messages(unquote(repo), queue, visibility_timeout_seconds)
      end

      @spec read_messages_with_poll(
              Pgmq.queue(),
              visibility_timeout_seconds :: integer(),
              count :: integer(),
              max_poll_seconds :: integer(),
              poll_interval_ms :: integer()
            ) :: [Pgmq.Message.t()]
      def read_messages_with_poll(
            queue,
            visibility_timeout_seconds,
            count,
            max_poll_seconds \\ @default_max_poll_seconds,
            poll_interval_ms \\ @default_poll_interval_ms
          ) do
        Pgmq.read_messages(
          unquote(repo),
          queue,
          visibility_timeout_seconds,
          max_poll_seconds,
          poll_interval_ms
        )
      end

      @spec archive_message(Pgmq.queue(), message :: Pgmq.Message.t() | message_id :: integer()) ::
              [Pgmq.Message.t()]
      def archive_message(queue, message) do
        Pgmq.archive_message(unquote(repo), queue, message)
      end

      @spec delete_messages(Pgmq.queue(), messages :: [Pgmq.Message.t()] | [integer()]) :: [
              Pgmq.Message.t()
            ]
      def delete_messages(queue, messages) do
        Pgmq.delete_messages(unquote(repo), queue, message)
      end

      # We can assume it was properly encoded as pgmq doesn't allow poorly encoded
      # messages to be published
      defp decode_message_content(message) do
        %Message{message | body: unquote(encoder).decode!(message.body)}
      end
    end
  end

  @spec create_queue(repo, queue) :: :ok | {:error, atom}
  def create_queue(repo, queue) do
    repo.query!("SELECT FROM pgmq_create($1)", [queue])
  end

  @spec drop_queue(repo, queue) :: :ok | {:error, atom}
  def drop_queue(repo, queue) do
    repo.query!("SELECT FROM pgmq_drop($1)", [queue])
  end

  @spec send_message(repo, queue, encoded_message :: binary) ::
          {:ok, Message.t()} | {:error, atom}
  def send_message(repo, queue, encoded_message) do
    repo.query!("SELECT FROM pgmq_send($1, $2)", [queue, encoded_message])
  end

  @spec read_message(repo, queue, visibility_timeout_seconds :: integer) ::
          {:ok, Message.t()} | {:error, atom}
  def read_message(repo, queue, visibility_timeout_seconds) do
    repo.query!("SELECT FROM pgmq_read($1, $2, 1)", [queue, visibility_timeout_seconds])
  end

  @spec read_messages(repo, queue, visibility_timeout_seconds :: integer, count :: integer) ::
          {:ok, [Message.t()]} | {:error, atom}
  def read_messages(repo, queue, visibility_timeout_seconds, count) do
    repo.query!("SELECT FROM pgmq_read($1, $2, $3)", [queue, visibility_timeout_seconds, count])
  end

  @spec read_messages_with_poll(
          repo,
          queue,
          count :: integer,
          visibility_timeout_seconds :: integer,
          count :: integer
        ) :: {:ok, [Message.t()]} | {:error, atom}
  def read_messages_with_poll(
        repo,
        queue,
        count,
        visibility_timeout_seconds,
        max_poll_seconds \\ @default_max_poll_seconds,
        poll_interval_ms \\ @default_poll_interval_ms
      ) do
    repo.query!("SELECT FROM pgmq_read_with_poll($1, $2, $3, $4, $5)", [
      queue,
      visibility_timeout_seconds,
      count,
      max_poll_seconds,
      poll_interval_ms
    ])
  end

  @spec archive_message(repo, queue, (message_id :: integer) | (message :: Message.t())) ::
          :ok | {:error, atom}
  def archive_message(repo, queue, %Message{id: message_id}) do
    archive_message(repo, queue, message_id)
  end

  def archive_message(repo, queue, message_id) do
    repo.query!("SELECT FROM pgmq_archive($1, $2)", [queue, message_id])
  end

  @spec delete_messages(repo, queue, [message_id :: integer] | [Message.t()]) ::
          :ok | {:error, atom}
  def delete_messages(repo, queue, [%Message{} | _] = messages) do
    message_ids = Enum.map(messages, fn m -> m.id end)
    delete_messages(repo, queue, message_ids)
  end

  def delete_messages(repo, queue, [message_id]) do
    repo.query!("SELECT FROM pgmq_delete($1::text, $2::bigint)", [queue, message_id])
  end

  def delete_messages(repo, queue, message_ids) do
    repo.query!("SELECT FROM pgmq_delete($1::text, $2::bigint[])", [queue, message_ids])
  end
end