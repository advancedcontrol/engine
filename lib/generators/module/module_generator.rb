class ModuleGenerator < Rails::Generators::NamedBase
	#source_root File.expand_path('../templates', __FILE__)
	
	def create_module_file
		
		name = file_name.downcase.gsub(/\s|-/, '_')
		param = class_path
		param.map! {|item| item.downcase.gsub(/\s|-/, '_')}
		
		path = File.join('app/modules', *param)
		
		scope = []
		text = ""
		param.map! {|item|
			item = item.camelcase
			scope << item
			text += "module #{scope.join('::')}; end\n"
			item
		}
		param << name.camelcase
		scope = param.join('::')
		
		
		create_file File.join(path, "#{name}.rb") do
			type = ask("What type of module (device, service, logic) will this be?")
			
			text += <<-FILE


class #{scope} < Orchestrator::#{type.downcase.camelcase}
	def on_load
	end
	
	def on_unload
	end
	
	def on_update
	end
end

			FILE
			
			text
		end
		
	end
end
