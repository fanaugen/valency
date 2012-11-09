###
# some project-specific jQuery plugins for interactive UI
# written in CoffeeScript
# requires jQuery v 1.7.2 or higher
###
(($) ->
	# inColumns jQuery Plugin
	# by Alexander Jahraus
	# usage: $('li').inColumns(nCols);
	# 
	# counts n elements and wraps them
	# in nCols <div>s evenly (n/nCols items per <div>)
	# tailored to work with Bootstrap's .dropdown-menu
	$.fn.inColumns = (nCols) ->
		# this is a collection of <li> nodes
		return this if (nItems = @length) < nCols
		perCol     = Math.ceil( nItems / nCols )
		# slice and wrap:
		totalWidth = i = 0
		while i < nCols
			($thisCol = @slice perCol * i, perCol * ++i).wrapAll '<div class="column"/>'
		# adjust widths: temporarily show dropdown (invisible)
		($menu = $thisCol.closest '.dropdown-menu').css display: 'block', opacity: 0
		# Firefox hack: add 1 pixel...
		$menu.width(1 + $menu.children('.column').toArray().reduce(
			(sum, next) ->
				sum + $(next).outerWidth()
			, 0)
		).children('li').not('.divider').width $menu.find('.column:first').outerWidth()
		$menu.css display: '', opacity: '' # reset display and opacity
		this
	
	# align_below_and_setup_toggle jQuery Plugin
	# by Alexander Jahraus
	# usage: $obj.align_below_and_setup_toggle()
	# find the immediately following element, align it directly below this
	# and set a slideToggle handler on click, updating the label of this
	$.fn.align_below_and_setup_toggle = ->
		$btn       = this
		$toggle_me = $btn.next() # could add optional selector here
		$parent    = $toggle_me.parent()
		offset     = $btn.offset()
		
		return this if $toggle_me.length < 1
		
		$toggle_me.offset
			'left': offset.left
			'top' : offset.top + $btn.outerHeight()
		.css
			'max-width': $parent.width() - offset.left + $parent.offset().left
			'min-width': "200px"
		.hide()
		
		$btn.click ->
			$toggle_me.slideToggle ->
				label = $btn.text()
				$btn.text label.replace(
					/(hide|show)/, if label.match(/hide/) then "show" else "hide"
				)
		this
	
	# flash: highlight an element for a split-second
	# by quickly changing and restoring its background-color
	$.fn.flash = (color = 'yellow', duration = 300) ->
		_it      = this # the jQuery object to flash
		restore  = _it.css('background-color')
		_it.queue (next)->
			_it.css('background-color', color); next()
		.queue (next)->
			_it.delay(duration); next()
		.queue (next)->
			_it.css('background-color', restore); next()
	
)(jQuery)