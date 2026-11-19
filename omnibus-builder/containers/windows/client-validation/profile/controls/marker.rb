control 'cinc-solo-marker' do
  describe file('C:/validation/cinc-solo-converged.txt') do
    it { should exist }
    its('content') { should cmp 'cinc solo validation passed' }
  end
end
