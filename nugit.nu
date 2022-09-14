export def remotes [] {
	git remote | lines
}

export def branches [] {
	git branch | lines | str trim | each {
		if ($in | str starts-with '* ') {
			{ cur: ' * ', name: ($in | str substring '2,') }
		} else {
			{ cur: '', name: $in }
		}
	}
}

export def delete [] {
	each { |branch| git branch -D $branch.name } |
		lines |
		parse -r '^Deleted branch (?P<deleted_branch>[^ ]+) \(was (?P<commit>[^\)]+)\).$'
}

export def switch [index: int] {
	git switch ($in.name | select $index)
}

def in_section [section: string] {
	skip until $it == $section | skip 1 | skip while $it =~ '^\(.+\)$' | take until ($it | empty?)
}

def parse_columns [stage: string] {
	parse -r '^(?P<changes>.+):\s+(?P<file>.+?)(?:\((?P<submodule>.+)\))?$' |
		update changes { if ($in.submodule | empty?) { $in.changes } else { $in.submodule } } |
		update file { $in.file | str trim } |
		select changes file |
		upsert stage $stage
}

export def status [] {
	let lines = (git status | lines | str trim);
	let staged = ($lines | in_section 'Changes to be committed:' | parse_columns staged)
	let not_staged = ($lines | in_section 'Changes not staged for commit:' | parse_columns unstaged)
	let not_tracked = ($lines | in_section 'Untracked files:' | wrap file | insert changes 'new file' |
		insert stage untracked | move changes --before file)
	let unmerged = ($lines | in_section 'Unmerged paths:' | parse_columns unstaged)
	$staged | append $not_staged | append $unmerged | append $not_tracked
}

export def add [] {
	let not_staged = ($in | where stage != 'staged')
	$not_staged | where changes == 'deleted' | each { git rm $in.file }
	$not_staged | where changes != 'deleted' | each { git add $in.file }
}

export def pr [] {
	git push --set-upstream (current_remote) (branches | where cur == ' * ').0.name
}

export def restore [from?: string, --force (-f)] {
	let restore_table = ($in | where ($it.changes == 'modified' || $it.changes == 'deleted'))
	if ($restore_table | empty?) {
		'nothing to restore'
	} else {
		let files_to_restore = $restore_table.file
		let operation = {
			$files_to_restore | each {
				if ($from == null) { git restore $in } else { git restore $'--source=($from)' --staged --worktree $in }
			}
		}
		if ($force) {
			do $operation
		} else {
			'following files will be reset to HEAD, proceed? (y/n)'
			$files_to_restore
			if (input) == 'y' {
				do $operation
			}
		}
	}
}

export def clean [--force (-f)] {
	let files_to_checkout = ($in | where changes == 'modified').file
	let operation = { $files_to_checkout | each { git checkout $in } }
	if ($force) {
		do $operation
	} else {
		'following files will be reset to HEAD, proceed? (y/n)'
		$files_to_checkout
		if (input) == 'y' {
			do $operation
		}
	}
}

def current_remote [] {
	let from_env = (env | where name == 'nugit_remote')
	if ($from_env | length) == 1 {
		$from_env.0.value
	} else {
		let rem = remotes
		if 'origin' in $rem {
			'origin'
		} else {
			if ($rem | length) == 1 { $rem.0 } else { 'error' }
		}
	}
}
