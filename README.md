# Interact

Another interaction library for Ruby, with an interesting twist: the user can
go back in time to re-answer questions.

*Copyright 2011, Alex Suraci. Licensed under the MIT license, please see the
LICENSE file. All rights reserved.*


## Basic Usage

```ruby
require "rubygems"
require "interact"

class MyInteractiveClass
  include Interactive::Rewindable

  def run
    first = ask "Some question?"
    second = ask "Boolean default?", :default => true
    third = ask "Stringy default?", :default => "foo"

    fourth = ask "Multiple choice?", :choices => ["foo", "bar", "fizz"]

    some_mutation = []

    fifth = ask "Multiple choice, indexed list?",
      :choices => ["foo", "bar", "fizz"],
      :indexed => true

    some_mutation << fifth

    finalize

    sixth = ask "Password", :echo => "*", :forget => true

    p [first, second, third, fourth, fifth, sixth]
  end
end

MyInteractiveClass.new.run
```

After running this, the user will be prompted with each question one-by-one.
Interact supports basic editing features such as going to the start/end,
editing in the middle of the text, backspace, forward delete, and
backwards-kill-word.

In addition, the user can hit the up arrow to go "back in time" and re-answer
questins.

Make sure you call `finalize` after doing any mutation performed based on user
input; this will prevent them from rewinding to before this took place. Or you
can just disable rewinding if it's too complicated (see below).

Anyway, here's an example session:

```
Some question?: hello<enter>
Boolean default? [Yn]: <up>
Some question? ["hello"]: trying again<enter>
Boolean default? [Yn]: n<enter>
Stringy default? ["foo"]: <up>
Boolean default? [yN]: y<enter>
Stringy default? ["foo"]: <enter>
Multiple choice? ("foo", "bar", "fizz"): f<enter>
Please disambiguate: foo or fizz?
Multiple choice? ("foo", "bar", "fizz"): fo<enter>
1: foo
2: bar
3: fizz
Multiple choice, indexed list?: 2<enter>
Password: ******<enter>
["trying again", true, "foo", "foo", "bar", "secret"]
```

Note that the user's previous answers become the new defaults for the question
if they rewind.

## Disabling Rewinding

Interact provides a nifty user-friendly "rewinding" feature, which allows the
user to go back in time and re-answer a question. If you don't want this
feature, simply call `disable_rewind` in your class. You can re-enable it with
`enable_rewind` in subclasses.

```ruby
class NoRewind
  include Interactive
  disable_rewind

  def run
    res = ask "Is there no return?", :default => true

    if res == rewind_enabled?
      puts "You're right!"
    else
      puts "Nope! It's disabled."
    end
  end
end

NoRewind.new.run
```
